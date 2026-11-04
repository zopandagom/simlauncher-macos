import AppLogInterface
import Core
import Foundation
import SimulatorInterface

/// `SimulatorClient.launchWithConsole` 로 iOS 앱을 실행하고 세션별 버퍼에 출력을 쌓는 `AppLogClient`.
/// 받기 작업은 세션마다 이 actor 가 만든 Task 이고 SimLauncher 가 켜져 있는 동안 이어진다 (`stopAll()` 로만 멈춘다).
/// 대체할 때 앞 세션의 받기는 **취소하지 않는다**: 앞 simctl 에 SIGINT 를 보내면 그 simctl 이 다루는 앱을 끄므로 새로 뜬 앱과 겹칠 위험이 있다.
/// 앞 simctl 은 새 실행·다시 설치가 앞 앱을 끝내면 스스로 끝나고(측정), 그때 대체 표시가 있으면 `.replaced` 다.
/// 판정은 "끝남이 오는 시점에 표시가 있느냐" 하나라 새 실행의 신호와 앞 simctl 의 끝 중 어느 쪽이 먼저여도 같다.
public actor AppLogClientImpl: AppLogClient {
  struct LineSubscriber {
    let continuation: AsyncStream<AppLogLineUpdate>.Continuation
    /// 이 번호까지 보냈다.
    var deliveredThrough: Int
  }

  private let simulator: any SimulatorClient
  let flushInterval: Duration
  private let launchSignalTimeout: Duration
  private nonisolated let running = RunningTasks()
  var table: AppLogSessionTable
  private var launchWaiters: [AppLogSessionID: CheckedContinuation<Result<Void, AppLogLaunchError>, Never>] = [:]
  private var timeoutTasks: [AppLogSessionID: Task<Void, Never>] = [:]
  var flushTasks: [AppLogSessionID: Task<Void, Never>] = [:]
  var lineSubscribers: [AppLogSessionID: [UUID: LineSubscriber]] = [:]
  var sessionSubscribers: [UUID: AsyncStream<[AppLogSessionSummary]>.Continuation] = [:]

  public init(simulator: any SimulatorClient) {
    self.init(
      simulator: simulator,
      limits: .standard,
      flushInterval: .milliseconds(100),
      launchSignalTimeout: .seconds(60)
    )
  }

  /// 테스트용: 상한·묶음 간격(`.zero` 면 곧바로 보낸다)·실행 신호 대기 상한을 바꾼다.
  /// 신호 대기 상한은 앱이 아무것도 찍지 않고 simctl 의 신호 줄 형식이 바뀐 경우에도 실행 요청이 갇히지 않게 하는 값이다
  /// (막 켠 기기에서 실행이 수 초 걸리는 것보다 충분히 길게).
  init(simulator: any SimulatorClient, limits: AppLogLimits, flushInterval: Duration, launchSignalTimeout: Duration) {
    self.simulator = simulator
    self.table = AppLogSessionTable(limits: limits)
    self.flushInterval = flushInterval
    self.launchSignalTimeout = launchSignalTimeout
  }

  // MARK: - 실행

  public func launchIOSApp(
    _ bundleID: AppBundleID,
    appName: String,
    on device: VirtualDevice.ID,
    deviceName: String
  ) async throws(AppLogLaunchError) -> AppLogSessionID {
    try await self.start(
      AppLogLaunchSpec(bundleID: bundleID, appName: appName, device: device, deviceName: deviceName)
    )
  }

  /// 기기를 켜지 않는다. 목록을 다시 읽어 그 기기가 켜져 있을 때만 Simulator 앱을 먼저 열어(실패는 무시) 실행 결과가 보이게 한다
  /// (설치 흐름의 켜기·앱 열기와 같은 결과를 켜기 없이). 꺼졌거나 없거나 목록을 읽지 못하면 앱을 열지 않는다: 켜진 기기가 없을 때
  /// Simulator 앱을 열면 앱이 기기를 켤 수 있다. 그때도 실행은 시도해 simctl 의 실패(`.deviceNotBooted` 등)를 그대로 던진다.
  public func relaunch(_ session: AppLogSessionID) async throws(AppLogLaunchError) -> AppLogSessionID {
    guard !self.running.isStopping else {
      throw .commandFailed
    }
    guard let record = self.table.record(session), record.isPublished else {
      throw .sessionNotFound
    }
    let inventory = try? await self.simulator.fetchInventory()
    if inventory?.devices.first(where: { $0.id == record.spec.device })?.state == .booted {
      try? await self.simulator.openSimulatorApp()
    }
    return try await self.start(record.spec)
  }

  public func replacementWillStart(_ bundleID: AppBundleID, on device: VirtualDevice.ID) {
    self.table.markInstall(AppLogSessionKey(target: .iOS(device), appID: bundleID.rawValue))
  }

  public func replacementCancelled(_ bundleID: AppBundleID, on device: VirtualDevice.ID) {
    self.table.unmarkInstall(AppLogSessionKey(target: .iOS(device), appID: bundleID.rawValue))
  }

  public nonisolated func stopAll() {
    self.running.stopAll()
  }

  /// 시작 중 세션을 넣고 받기 작업을 띄운 뒤, 실행 신호·실패·신호 대기 상한 중 먼저 온 것을 기다린다 (부른 Task 의 취소는 받지 않는다).
  private func start(_ spec: AppLogLaunchSpec) async throws(AppLogLaunchError) -> AppLogSessionID {
    guard !self.running.isStopping else {
      throw .commandFailed
    }
    let id = AppLogSessionID(UUID())
    let summary = AppLogSessionSummary(
      id: id,
      target: .iOS(spec.device),
      deviceName: spec.deviceName,
      appID: spec.bundleID.rawValue,
      appName: spec.appName,
      startedAt: Date(),
      state: .receiving
    )
    self.table.begin(summary, spec: spec)
    let result = await withCheckedContinuation { continuation in
      // 기다리는 쪽을 먼저 넣고 작업을 띄운다 (작업의 알림은 이 actor 를 거치므로 이 블록이 끝난 뒤에 온다).
      self.launchWaiters[id] = continuation
      self.startReceiving(id, spec: spec)
      self.startSignalTimer(id)
    }
    try result.get()
    return id
  }

  private func startReceiving(_ id: AppLogSessionID, spec: AppLogLaunchSpec) {
    let simulator = self.simulator
    let task = Task {
      let end: Result<AppConsoleEnd, SimulatorError>
      do throws(SimulatorError) {
        end = try await .success(
          simulator.launchWithConsole(spec.bundleID, on: spec.device) { event in
            await self.receive(event, for: id)
          }
        )
      } catch {
        end = .failure(error)
      }
      await self.finished(id, end)
    }
    if !self.running.insert(id, task) {
      // `stopAll()` 이 그 사이 왔다: 띄우자마자 멈춘다 (시작 전이면 simctl 을 실행하지 않는다).
      task.cancel()
    }
  }

  private func startSignalTimer(_ id: AppLogSessionID) {
    let timeout = self.launchSignalTimeout
    self.timeoutTasks[id] = Task {
      try? await Task.sleep(for: timeout)
      guard !Task.isCancelled else { return }
      await self.signalTimedOut(id)
    }
  }

  /// 신호도 끝남도 없이 상한이 지났다: simctl 은 그대로 두고 실행된 것으로 본다.
  private func signalTimedOut(_ id: AppLogSessionID) {
    self.timeoutTasks[id] = nil
    guard self.launchWaiters[id] != nil else { return }
    self.publish(id)
    self.resolveLaunch(id, .success(()))
  }

  private func resolveLaunch(_ id: AppLogSessionID, _ result: Result<Void, AppLogLaunchError>) {
    self.timeoutTasks.removeValue(forKey: id)?.cancel()
    self.launchWaiters.removeValue(forKey: id)?.resume(returning: result)
  }

  // MARK: - 받기

  private func receive(_ event: AppConsoleEvent, for id: AppLogSessionID) {
    switch event {
    case .launched:
      guard self.launchWaiters[id] != nil else { return }
      self.publish(id)
      self.resolveLaunch(id, .success(()))
    case let .lines(texts):
      guard self.table.append(texts, to: id) else { return }
      self.scheduleFlush(id)
    }
  }

  /// simctl 이 끝났다 (받기 작업의 끝).
  private func finished(_ id: AppLogSessionID, _ end: Result<AppConsoleEnd, SimulatorError>) async {
    self.running.remove(id)
    guard let record = self.table.record(id) else { return }
    switch end {
    case .success(.stopped):
      guard record.isPublished else {
        self.discard(id, failure: .commandFailed)
        return
      }
      self.endSession(id, reason: .stopped)
    case .success(.exited):
      // 신호 없이 0 으로 끝나도 실행은 된 것으로 본다.
      if !record.isPublished {
        self.publish(id)
        self.resolveLaunch(id, .success(()))
      }
      await self.judgeEnd(id)
    case let .failure(error):
      guard record.isPublished else {
        self.discard(id, failure: AppLogLaunchError(error))
        return
      }
      // 신호 대기 상한 뒤의 실패: 실패 알림은 이미 지나 끝남으로만 보인다.
      await self.judgeEnd(id)
    }
  }

  /// 끝난 이유: 대체 표시가 있으면 `.replaced` (목록을 읽지 않는다). 아니면 목록을 다시 읽어 기기가 없거나 켜져 있지 않으면
  /// `.deviceShutDown` (끝난 직후 상태는 `Shutting Down`, 측정), 켜져 있거나 읽지 못하면 `.appExited`.
  private func judgeEnd(_ id: AppLogSessionID) async {
    guard let record = self.table.record(id) else { return }
    if self.table.isReplacing(id) {
      self.endSession(id, reason: .replaced)
      return
    }
    let reason: AppLogEndReason
    do {
      let inventory = try await self.simulator.fetchInventory()
      let device = inventory.devices.first { $0.id == record.spec.device }
      reason = device?.state == .booted ? .appExited : .deviceShutDown
    } catch {
      reason = .appExited
    }
    self.endSession(id, reason: reason)
  }

  private func discard(_ id: AppLogSessionID, failure: AppLogLaunchError) {
    self.flushTasks.removeValue(forKey: id)?.cancel()
    self.table.discard(id)
    self.resolveLaunch(id, .failure(failure))
  }

  private func publish(_ id: AppLogSessionID) {
    guard let removed = self.table.publish(id) else { return }
    for removedID in removed {
      self.finishLineSubscribers(of: removedID)
    }
    self.broadcastSessions()
  }

  /// 남은 줄을 곧바로 보내고 끝냄으로 바꾼다.
  private func endSession(_ id: AppLogSessionID, reason: AppLogEndReason) {
    self.flushTasks.removeValue(forKey: id)?.cancel()
    self.flush(id)
    if self.table.end(id, reason: reason) {
      self.broadcastSessions()
    }
  }
}
