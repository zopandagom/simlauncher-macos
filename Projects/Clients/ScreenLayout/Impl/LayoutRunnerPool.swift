import CommandInterface
import Core
import Foundation
import ScreenLayoutInterface
import SimulatorInterface
import Synchronization

/// 기기별 iOS 레이아웃 러너(상주 `xcodebuild test-without-building`)의 수명.
///
/// 상태: 없음(미실행) → `.preparing`(빌드·남은 러너 정리·launch·ready 대기) → `.ready`(감시 Task 가 2초마다 생존 확인)
/// → `.stopping`(quit/SIGTERM → uninstall) → 없음. 켜진 기기의 남은 러너 정리는 `.cleaning`.
/// 규칙 (설계 5.0): 상태 판정과 그 결과로 바꿀 상태를 await 없이 한 구간에서 끝낸 뒤에야 await 하고, await 뒤에는 상태를 다시 읽는다.
/// 상태를 지울 때는 아직 그 Attempt/Task 일 때만 지운다. 준비·멈춤·정리는 호출과 떨어진 비구조 Task 라 호출이 취소돼도 계속한다
/// (호출은 `CancellableWait` 로 기다려 곧바로 `.cancelled`).
/// 멈출 때마다 러너 앱을 `simctl uninstall` 로 지운다 (꺼진 기기면 실패하고 무시한다. 다음 켜짐의 정리가 지운다).
actor LayoutRunnerPool {
  /// 준비된 러너 하나.
  struct Session: Hashable, Sendable {
    let deviceID: VirtualDevice.ID
    let buildKey: String
    /// 이 세션의 ready.json 을 가려내는 토큰 (UUID). 세션이 바뀌었는지도 이것으로 본다.
    let token: String
    let process: LaunchedProcess
    let runnerPID: Int32
    let scale: Double
    let directory: URL

    var udid: String {
      self.deviceID.rawValue
    }
  }

  /// 준비 한 번. `process` 는 launch 뒤에 채운다. `stopRequested` 는 끄기·앱 종료가 세운다.
  struct Attempt: Sendable {
    let id: UUID
    /// 이 준비가 쓰는 빌드 키 (다른 기기의 빌드가 옛 키 빌드를 지우지 않게 `keep` 에 넣는다).
    let key: String
    let task: Task<Result<Session, ScreenLayoutError>, Never>
    var process: LaunchedProcess?
    var stopRequested = false
  }

  enum Runner: Sendable {
    case preparing(Attempt)
    case ready(Session, monitor: Task<Void, Never>)
    case stopping(UUID, Task<Void, Never>)
    case cleaning(UUID, Task<Void, Never>)
  }

  /// 준비됨 러너를 멈추는 방법.
  enum StopMode: Sendable {
    /// quit 요청 → `quitGrace` 안에 끝나지 않으면 SIGTERM (끄기·앱 종료·Xcode 바뀜).
    case graceful
    /// 곧바로 SIGTERM (러너 죽음·요청 시간 초과).
    case terminate
    /// xcodebuild 가 이미 끝났다 (유휴 자체 종료 등). uninstall 만.
    case exited
  }

  let simulator: any SimulatorClient
  let command: any CommandClient
  let buildCache: LayoutRunnerBuildCache
  let timing: IOSLayoutTiming
  let baseEnvironment: [String: String]
  /// `<러너 폴더>/sessions`.
  let sessionsRoot: URL

  var runners: [VirtualDevice.ID: Runner] = [:] {
    didSet { self.updateActiveCount() }
  }

  /// Launcher "끄기" 진행 중 (willShutDown ~ didShutDown). 새 준비·정리를 받지 않는다.
  var shuttingDown: Set<VirtualDevice.ID> = []
  /// 앱 종료가 정해져 러너를 모두 멈추는 중 (`stopAll`). 앱이 곧 끝나므로 되돌리지 않고, 새 준비를 받지 않는다
  /// (종료를 기다리는 사이 새로 고침이 xcodebuild 를 띄워 고아로 남기지 않게).
  var terminating = false
  /// 이번 켜짐에서 정리를 시작했거나 러너가 있었던 기기.
  var cleanedThisBoot: Set<VirtualDevice.ID> = []
  private var lastListedSequence: UInt64 = 0
  /// 준비 중·준비됨·멈추는 중 수 (정리 중은 세지 않는다). 동기 읽기용.
  private let activeCount = Mutex<Int>(0)
  private let listedSequence = Mutex<UInt64>(0)

  /// 파일·명령을 건드리지 않는다.
  init(
    simulator: any SimulatorClient,
    command: any CommandClient,
    runnerDirectory: URL,
    timing: IOSLayoutTiming,
    baseEnvironment: [String: String]
  ) {
    self.simulator = simulator
    self.command = command
    self.timing = timing
    self.baseEnvironment = baseEnvironment
    self.sessionsRoot = runnerDirectory.appending(path: "sessions", directoryHint: .isDirectory)
    self.buildCache = LayoutRunnerBuildCache(
      root: runnerDirectory.appending(path: "builds", directoryHint: .isDirectory),
      command: command,
      baseEnvironment: baseEnvironment,
      timeout: timing.buildTimeout
    )
  }

  /// 준비 중·준비됨·멈추는 중인 러너가 하나라도 있다.
  nonisolated var hasActiveRunners: Bool {
    self.activeCount.withLock { $0 > 0 }
  }

  /// `devicesListed` 에 붙일 다음 순번 (동기). 부른 순서대로 커진다.
  nonisolated func nextListedSequence() -> UInt64 {
    self.listedSequence.withLock { value in
      value += 1
      return value
    }
  }

  // MARK: - 세션 얻기

  /// 세션을 얻으려고 지금 상태에서 할 일.
  private enum Step {
    case ready(Session)
    case attempt(Task<Result<Session, ScreenLayoutError>, Never>)
    case transition(Task<Void, Never>)
    /// 상태를 바꿨다 (다시 읽는다).
    case again
  }

  /// 준비된 세션. 새로 띄우거나 띄우는 중·멈추는 중·정리 중이면 `onPreparing` 을 한 번 알리고 기다린다
  /// (호출한 Task 가 취소되면 기다림만 그만두고 `.cancelled`. 준비·멈춤·정리는 계속한다).
  /// 빌드 키가 다른 준비됨 러너(Xcode·소스 바뀜)는 정상 멈춤 뒤 새로 준비한다. 끄는 중인 기기는 준비하지 않고 `.deviceNotBooted`.
  func session(
    for id: VirtualDevice.ID,
    xcode: XcodeInstallation,
    onPreparing: @escaping @Sendable () async -> Void
  ) async throws(ScreenLayoutError) -> Session {
    let key = Self.buildKey(for: xcode)
    var announced = false
    while true {
      guard !Task.isCancelled else { throw .cancelled }
      let step = try self.step(for: id, xcode: xcode, key: key)
      if case let .ready(session) = step {
        return session
      }
      if case .again = step {
        continue
      }
      if !announced {
        announced = true
        await onPreparing()
      }
      if case let .attempt(task) = step {
        return try await CancellableWait.value(of: task).get()
      }
      // 멈춤·정리의 uninstall 이 새 러너를 지우지 않게 끝을 기다린 뒤 상태를 다시 읽는다.
      if case let .transition(task) = step, await !CancellableWait.finished(task) {
        throw .cancelled
      }
    }
  }

  /// 상태를 읽고, 바꿀 것(새 Attempt·정상 멈춤 시작)은 await 없이 바꾼다.
  private func step(for id: VirtualDevice.ID, xcode: XcodeInstallation, key: String) throws(ScreenLayoutError) -> Step {
    switch self.runners[id] {
    case nil:
      guard !self.shuttingDown.contains(id) else { throw .deviceNotBooted }
      guard !self.terminating else { throw .inspectorSetupFailed }
      return .attempt(self.startAttempt(id, xcode: xcode, key: key))
    case let .preparing(attempt):
      // 이미 멈추기로 한 준비(끄기·앱 종료)에는 합류하지 않는다: 끝나기를 기다린 뒤 상태를 다시 읽어 새로 준비한다
      // (끄기 → 다시 켜기 사이에 남은 준비에 붙어 실패하지 않게).
      if attempt.stopRequested {
        let task = attempt.task
        return .transition(Task { _ = await task.value })
      }
      return .attempt(attempt.task)
    case let .ready(session, _):
      // 감시가 알아채기 전(최대 monitorInterval)에 xcodebuild 가 이미 끝났으면(유휴 자체 종료 등) 요청하지 않고 멈춘 뒤 새로 준비한다.
      if self.command.exitStatus(session.process) != nil {
        self.beginStop(id, mode: .exited)
        return .again
      }
      if session.buildKey == key {
        return .ready(session)
      }
      self.beginStop(id, mode: .graceful)
      return .again
    case let .stopping(_, task), let .cleaning(_, task):
      return .transition(task)
    }
  }

  // MARK: - 요청

  /// 세션에 요청을 쓰고 맞는 id 의 응답을 기다린다. 기다리는 중 세션이 바뀌면(멈춤) 곧바로 실패
  /// (끄는 중·꺼짐이면 `.deviceNotBooted`, 아니면 `.inspectorSetupFailed`). `requestTimeout` 이 지나면 러너를 SIGTERM 으로
  /// 멈추고(uninstall 까지 기다린다) `.timedOut`. id 가 빈 응답·형식이 틀린 응답은 곧바로 `.unreadable`.
  func request(
    _ command: LayoutRunnerProtocol.Command,
    to session: Session
  ) async throws(ScreenLayoutError) -> LayoutRunnerProtocol.Response {
    guard self.isCurrent(session) else { throw await self.lostSessionError(session.deviceID) }
    let requestID = UUID().uuidString
    let response = session.directory.appending(path: LayoutRunnerProtocol.responseFile)
    try? FileManager.default.removeItem(at: response)
    do {
      try Self.writeRequest(command, id: requestID, in: session.directory)
    } catch {
      throw .unreadable
    }
    let clock = ContinuousClock()
    let start = clock.now
    while true {
      do {
        try await Task.sleep(for: self.timing.responsePollInterval)
      } catch {
        throw .cancelled
      }
      guard self.isCurrent(session) else { throw await self.lostSessionError(session.deviceID) }
      switch await Self.readResponse(at: response, id: requestID) {
      case .pending:
        break
      case .rejected:
        throw .unreadable
      case let .response(value):
        return value
      }
      if clock.now - start >= self.timing.requestTimeout {
        await self.beginStop(session.deviceID, mode: .terminate)?.value
        throw .timedOut
      }
    }
  }

  func isCurrent(_ session: Session) -> Bool {
    guard case let .ready(current, _) = self.runners[session.deviceID] else { return false }
    return current.token == session.token
  }

  /// 세션을 잃은 이유: 끄는 중이거나 목록에서 켜져 있지 않으면 `.deviceNotBooted`, 아니면 `.inspectorSetupFailed`.
  func lostSessionError(_ id: VirtualDevice.ID) async -> ScreenLayoutError {
    await self.classify(.inspectorSetupFailed, for: id)
  }

  /// 준비 실패(`.inspectorSetupFailed`)를 기기 상태로 다시 가린다. 그 밖의 실패는 그대로.
  func classify(_ error: ScreenLayoutError, for id: VirtualDevice.ID) async -> ScreenLayoutError {
    guard error == .inspectorSetupFailed else { return error }
    if self.shuttingDown.contains(id) {
      return .deviceNotBooted
    }
    return await self.isBooted(id) ? .inspectorSetupFailed : .deviceNotBooted
  }

  // MARK: - 도우미

  private func updateActiveCount() {
    let count = self.runners.values.count { runner in
      if case .cleaning = runner {
        false
      } else {
        true
      }
    }
    self.activeCount.withLock { $0 = count }
  }

  /// 목록에서 그 기기가 켜져 있는지. 목록을 읽지 못하면 켜진 것으로 본다 (모르면 멈추지 않는다).
  func isBooted(_ id: VirtualDevice.ID) async -> Bool {
    do throws(SimulatorError) {
      let inventory = try await self.simulator.fetchInventory()
      return inventory.devices.first { $0.id == id }?.state == .booted
    } catch {
      return true
    }
  }

  func sessionDirectory(_ id: VirtualDevice.ID) -> URL {
    self.sessionsRoot.appending(path: id.rawValue, directoryHint: .isDirectory)
  }

  /// 러너 앱을 지운다. 실패(SimLauncher 밖에서 꺼진 기기 405 등)는 사용자에게 알리지 않고, 정리 표시를 지워
  /// 다음에 목록이 그 기기를 켜진 것으로 읽을 때 다시 정리하게 한다 (목록을 다시 읽기 전에 밖에서 다시 켜도 남지 않게).
  func uninstallRunner(_ id: VirtualDevice.ID) async {
    guard let bundleID = AppBundleID(IOSLayoutRunner.appBundleID) else { return }
    do throws(SimulatorError) {
      try await self.simulator.uninstall(bundleID, on: id)
    } catch {
      self.cleanedThisBoot.remove(id)
    }
  }

  /// 이 Xcode 와 동봉 소스의 빌드 키 (version.plist 를 읽는다).
  static func buildKey(for xcode: XcodeInstallation) -> String {
    let plist = try? Data(contentsOf: LayoutRunnerCommands.versionPlist(xcode))
    return LayoutRunnerCommands.buildKey(
      productBuildVersion: plist.flatMap(LayoutRunnerCommands.productBuildVersion(fromVersionPlist:)),
      sourceDigest: LayoutRunnerSource.digest,
      xcodePath: xcode.bundleURL.path(percentEncoded: false)
    )
  }

  /// `request.json.tmp` 에 쓰고 `rename(2)` 로 내놓는다 (있는 파일도 원자적으로 바뀐다).
  static func writeRequest(_ command: LayoutRunnerProtocol.Command, id: String, in directory: URL) throws {
    let destination = directory.appending(path: LayoutRunnerProtocol.requestFile)
    let temporary = directory.appending(path: LayoutRunnerProtocol.requestFile + ".tmp")
    try LayoutRunnerProtocol.requestData(id: id, command: command).write(to: temporary)
    guard rename(temporary.path(percentEncoded: false), destination.path(percentEncoded: false)) == 0 else {
      throw CocoaError(.fileWriteUnknown)
    }
  }

  /// 크기를 먼저 보고(상한을 넘으면 거절) 읽어 해석한다. 메인·actor 밖에서 돈다.
  @concurrent
  nonisolated static func readResponse(at url: URL, id: String) async -> LayoutRunnerProtocol.ResponseRead {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
          let size = attributes[.size] as? Int
    else {
      return .pending
    }
    guard size <= LayoutRunnerProtocol.maxResponseBytes else { return .rejected }
    guard let data = try? Data(contentsOf: url) else { return .pending }
    return LayoutRunnerProtocol.response(from: data, id: id)
  }
}

// MARK: - 기기 수명 알림

extension LayoutRunnerPool {
  /// Launcher "끄기" 직전. 끄는 중 표시를 세우고 러너를 멈춘다. 띄우기 전 준비·정리 중·러너 없음은 곧바로 돌아온다.
  func willShutDown(_ id: VirtualDevice.ID) async {
    self.shuttingDown.insert(id)
    switch self.runners[id] {
    case nil, .cleaning:
      return
    case var .preparing(attempt):
      attempt.stopRequested = true
      self.runners[id] = .preparing(attempt)
      guard let process = attempt.process else { return }
      self.command.terminate(process)
      _ = await attempt.task.value
    case .ready:
      await self.beginStop(id, mode: .graceful)?.value
    case let .stopping(_, task):
      await task.value
    }
  }

  /// Launcher "끄기" 가 끝난 뒤 (성공·실패 모두).
  func didShutDown(_ id: VirtualDevice.ID) {
    self.shuttingDown.remove(id)
  }

  /// iOS 기기 목록을 읽은 뒤. 순번이 이미 처리한 것보다 오래되면 버린다 (늦게 도착한 옛 목록).
  /// 켜진 기기 중 이번 켜짐에서 처음 보고 러너가 없고 끄는 중이 아닌 기기는 남은 러너 앱을 정리한다 (기다리지 않는다).
  /// 켜진 것으로 없는 기기는 정리 표시를 지워 다음 켜짐에 다시 정리한다.
  func devicesListed(_ booted: Set<VirtualDevice.ID>, sequence: UInt64) {
    guard sequence > self.lastListedSequence else { return }
    self.lastListedSequence = sequence
    self.cleanedThisBoot.formIntersection(booted)
    for id in booted where LayoutRunnerCommands.isUDID(id.rawValue) && !self.shuttingDown.contains(id) {
      guard !self.cleanedThisBoot.contains(id) else { continue }
      self.cleanedThisBoot.insert(id)
      if self.runners[id] == nil {
        self.startCleaning(id)
      }
    }
  }

  /// 모든 러너를 멈추고 지운다. 빌드는 취소만, 정리 중은 기다리지 않는다. `stopAllLimit` 이 지나면 돌아온다 (멈춤은 계속).
  func stopAll() async {
    self.terminating = true
    var waits: [Task<Void, Never>] = []
    for (id, runner) in self.runners {
      switch runner {
      case var .preparing(attempt):
        attempt.stopRequested = true
        self.runners[id] = .preparing(attempt)
        if let process = attempt.process {
          self.command.terminate(process)
        }
        let task = attempt.task
        waits.append(Task { _ = await task.value })
      case .ready:
        if let task = self.beginStop(id, mode: .graceful) {
          waits.append(task)
        }
      case let .stopping(_, task):
        waits.append(task)
      case .cleaning:
        break
      }
    }
    await self.buildCache.cancelAll()
    let all = Task {
      for wait in waits {
        await wait.value
      }
    }
    _ = await CancellableWait.finished(all, timeout: self.timing.stopAllLimit)
  }
}
