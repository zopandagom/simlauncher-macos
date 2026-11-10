import CommandInterface
import Core
import Foundation
import ScreenLayoutInterface

// MARK: - 멈춤·감시·남은 러너 정리

extension LayoutRunnerPool {
  /// 준비됨 러너를 멈추기 시작한다 (await 없이 `.stopping` 으로 바꾼다). 준비됨이 아니면 nil.
  /// 멈춤 Task: (방법에 따라) quit·SIGTERM → uninstall → 아직 그 Task 면 상태를 지운다.
  @discardableResult
  func beginStop(_ id: VirtualDevice.ID, mode: StopMode) -> Task<Void, Never>? {
    guard case let .ready(session, monitor) = self.runners[id] else { return nil }
    monitor.cancel()
    let stopID = UUID()
    let task = Task { await self.stop(session, mode: mode, stopID: stopID) }
    self.runners[id] = .stopping(stopID, task)
    return task
  }

  private func stop(_ session: Session, mode: StopMode, stopID: UUID) async {
    var exited = true
    switch mode {
    case .graceful:
      try? Self.writeRequest(.quit, id: UUID().uuidString, in: session.directory)
      try? FileManager.default.removeItem(at: session.directory.appending(path: LayoutRunnerProtocol.responseFile))
      if await !self.waitForExit(session.process, within: self.timing.quitGrace) {
        self.command.terminate(session.process)
        exited = await self.waitForExit(session.process, within: self.timing.terminateGrace)
      }
    case .terminate:
      self.command.terminate(session.process)
      exited = await self.waitForExit(session.process, within: self.timing.terminateGrace)
    case .exited:
      break
    }
    Self.removeScreenData(in: session.directory)
    if !exited {
      self.removeScreenDataAfterExit(session.process, session.deviceID, owner: .stop(stopID))
    }
    await self.uninstallRunner(session.deviceID)
    if case let .stopping(current, _) = self.runners[session.deviceID], current == stopID {
      self.runners[session.deviceID] = nil
    }
  }

  /// 준비됨 동안 `monitorInterval` 마다: xcodebuild 가 끝났으면(유휴 자체 종료 등) uninstall 만, 러너 pid 가 죽었으면(기기 꺼짐·충돌)
  /// SIGTERM → uninstall. 멈춤을 시작하면 이 Task 는 끝난다. 세션이 바뀌었으면 아무것도 하지 않고 끝난다.
  func monitor(_ id: VirtualDevice.ID, token: String) async {
    while !Task.isCancelled {
      try? await Task.sleep(for: self.timing.monitorInterval)
      guard !Task.isCancelled, let session = self.readySession(id, token: token) else { return }
      if self.command.exitStatus(session.process) != nil {
        self.beginStop(id, mode: .exited)
        return
      }
      let alive = await self.isRunnerAlive(pid: session.runnerPID, udid: session.udid)
      guard !Task.isCancelled, self.readySession(id, token: token) != nil else { return }
      if !alive {
        self.beginStop(id, mode: .terminate)
        return
      }
    }
  }

  private func readySession(_ id: VirtualDevice.ID, token: String) -> Session? {
    guard case let .ready(session, _) = self.runners[id], session.token == token else { return nil }
    return session
  }

  /// `within` 안에 끝나면 true. 끝나지 않아도 프로세스는 건드리지 않는다.
  func waitForExit(_ process: LaunchedProcess, within limit: Duration) async -> Bool {
    let command = self.command
    let waiter = Task { _ = await command.waitForExit(process) }
    let finished = await CancellableWait.finished(waiter, timeout: limit)
    waiter.cancel()
    return finished
  }

  // MARK: 늦게 쓰이는 화면 데이터 정리

  /// 취소한 요청의 늦은 응답을 지운다: 그 id 의 응답이 오면 지우고, 세션이 바뀌거나(멈춤이 폴더를 비운다) `requestTimeout` 이
  /// 지나면 그만둔다. 다른 id 의 응답(새 요청)은 건드리지 않는다. 상태를 바꾸지 않는 정리 Task 다.
  func discardLateResponse(_ requestID: String, session: Session) {
    Task { await self.awaitLateResponse(requestID, session: session) }
  }

  private func awaitLateResponse(_ requestID: String, session: Session) async {
    let response = session.directory.appending(path: LayoutRunnerProtocol.responseFile)
    let clock = ContinuousClock()
    let deadline = clock.now + self.timing.requestTimeout
    while clock.now < deadline, self.isCurrent(session) {
      try? await Task.sleep(for: self.timing.responsePollInterval)
      guard self.isCurrent(session) else { return }
      switch await Self.readResponse(at: response, id: requestID) {
      case .pending:
        continue
      case .rejected:
        // id 를 확인하기 전에 거절되는 응답(빈 id·크기 초과)은 새 요청의 것일 수 있어 건드리지 않는다 (새 요청이 판정해 지운다).
        return
      case .response:
        try? FileManager.default.removeItem(at: response)
        return
      }
    }
  }

  /// 늦은 파일 정리를 맡긴 쪽. 그 기기 상태가 아직 이 주인이거나 비어 있을 때만 지운다 (그 뒤의 새 세션 파일은 건드리지 않는다).
  enum ScreenDataOwner: Equatable {
    case stop(UUID)
    case attempt(UUID)
  }

  /// SIGTERM 뒤 상한 안에 끝나지 않은 xcodebuild 가 끝나며 쓰는 파일(결과 번들·로그)도 지운다: 끝나기를 기다렸다가
  /// `removeScreenDataIfOwned` 로 세션 폴더를 다시 비운다. 상태를 바꾸지 않는다.
  func removeScreenDataAfterExit(_ process: LaunchedProcess, _ id: VirtualDevice.ID, owner: ScreenDataOwner) {
    let command = self.command
    Task {
      _ = await command.waitForExit(process)
      await self.removeScreenDataIfOwned(id, owner: owner)
    }
  }

  /// 기기 상태가 비었거나 아직 `owner`(그 멈춤·그 준비)이면 세션 폴더를 비운다. 다른 세션의 준비·준비됨·멈춤·정리 중이면 그대로 둔다.
  func removeScreenDataIfOwned(_ id: VirtualDevice.ID, owner: ScreenDataOwner) {
    let owned = switch self.runners[id] {
    case nil: true
    case let .stopping(stopID, _): owner == .stop(stopID)
    case let .preparing(attempt): owner == .attempt(attempt.id)
    case .ready, .cleaning: false
    }
    if owned {
      Self.removeScreenData(in: self.sessionDirectory(id))
    }
  }

  // MARK: 켜진 기기의 남은 러너 정리

  /// 상태를 `.cleaning` 으로 바꾸고(await 없이) 정리 Task 를 띄운다: 남은 세션 quit → 세션 폴더 지우기 → uninstall(오류 무시).
  func startCleaning(_ id: VirtualDevice.ID) {
    let cleanID = UUID()
    let task = Task { await self.clean(id, cleanID: cleanID) }
    self.runners[id] = .cleaning(cleanID, task)
  }

  private func clean(_ id: VirtualDevice.ID, cleanID: UUID) async {
    let directory = self.sessionDirectory(id)
    await self.quitOrphanRunner(udid: id.rawValue, directory: directory)
    try? FileManager.default.removeItem(at: directory)
    await self.uninstallRunner(id)
    if case let .cleaning(current, _) = self.runners[id], current == cleanID {
      self.runners[id] = nil
    }
  }

  /// SimLauncher 가 비정상 종료해 남은 러너 (같은 기기에 두 xcodebuild 가 겹치면 둘 다 실패한다, 실측):
  /// 세션 폴더의 이전 ready.json(토큰은 보지 않는다)의 pid 가 이 기기의 러너로 살아 있으면 quit 요청을 쓰고
  /// `orphanQuitWait` 동안 끝나기를 기다린다. 폴더는 부른 쪽이 지운다.
  func quitOrphanRunner(udid: String, directory: URL) async {
    let readyURL = directory.appending(path: LayoutRunnerProtocol.readyFile)
    guard let data = try? Data(contentsOf: readyURL),
          let ready = LayoutRunnerProtocol.ready(from: data, token: nil),
          await self.isRunnerAlive(pid: ready.pid, udid: udid)
    else {
      return
    }
    try? Self.writeRequest(.quit, id: UUID().uuidString, in: directory)
    let clock = ContinuousClock()
    let deadline = clock.now + self.timing.orphanQuitWait
    while clock.now < deadline {
      try? await Task.sleep(for: self.timing.orphanPollInterval)
      if await !self.isRunnerAlive(pid: ready.pid, udid: udid) {
        return
      }
    }
  }

  /// `ps -p <pid> -o comm=` 로 이 기기의 러너가 살아 있는지. ps 를 실행하지 못하면 살아 있는 것으로 본다 (모르면 멈추지 않는다).
  func isRunnerAlive(pid: Int32, udid: String) async -> Bool {
    do throws(CommandError) {
      let result = try await self.command.run(
        LayoutRunnerCommands.psExecutable,
        LayoutRunnerCommands.psArguments(pid: pid),
        environment: self.baseEnvironment
      )
      return LayoutRunnerCommands.isRunnerAlive(result, udid: udid)
    } catch {
      return true
    }
  }
}
