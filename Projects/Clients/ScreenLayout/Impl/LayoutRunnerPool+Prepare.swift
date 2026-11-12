import CommandInterface
import Core
import Foundation
import ScreenLayoutInterface
import SimulatorInterface

// MARK: - 준비 (미실행 → 준비 중 → 준비됨)

extension LayoutRunnerPool {
  /// 준비 Attempt 를 만들고 상태를 `.preparing` 으로 바꾼다 (await 없이). Attempt Task 는 actor 위에서 이 메서드가 끝난 뒤 시작한다.
  func startAttempt(_ id: VirtualDevice.ID, xcode: XcodeInstallation, key: String) -> Task<
    Result<Session, ScreenLayoutError>,
    Never
  > {
    let attemptID = UUID()
    let task = Task {
      await self.runAttempt(id, attemptID: attemptID, xcode: xcode, key: key)
    }
    self.runners[id] = .preparing(Attempt(id: attemptID, key: key, task: task))
    self.cleanedThisBoot.insert(id)
    return task
  }

  /// 준비하고, 끝나면 상태를 정한다: 성공이면 감시 Task 와 함께 `.ready`, 실패(또는 끝에 멈춤 요청)면 띄운 프로세스에 SIGTERM·uninstall 뒤 지운다.
  private func runAttempt(
    _ id: VirtualDevice.ID,
    attemptID: UUID,
    xcode: XcodeInstallation,
    key: String
  ) async -> Result<Session, ScreenLayoutError> {
    let error: ScreenLayoutError
    do throws(ScreenLayoutError) {
      let session = try await self.prepare(id, attemptID: attemptID, xcode: xcode, key: key)
      if let attempt = self.attempt(id, attemptID), !attempt.stopRequested {
        let monitor = Task { await self.monitor(id, token: session.token) }
        self.runners[id] = .ready(session, monitor: monitor)
        return .success(session)
      }
      error = .inspectorSetupFailed
    } catch let caught {
      error = caught
    }
    if let process = self.attempt(id, attemptID)?.process {
      if self.command.exitStatus(process) == nil {
        self.command.terminate(process)
      }
      let exited = await self.waitForExit(process, within: self.timing.terminateGrace)
      Self.removeScreenData(in: self.sessionDirectory(id))
      if !exited {
        self.removeScreenDataAfterExit(process, id, owner: .attempt(attemptID))
      }
      await self.uninstallRunner(id)
    }
    let classified = await self.classify(error, for: id)
    if self.attempt(id, attemptID) != nil {
      self.runners[id] = nil
    }
    return .failure(classified)
  }

  /// 빌드 → 멈춤 확인 → 남은 러너 정리 → 세션 폴더 새로 → 켜짐 확인 → 멈춤 확인 → launch → 멈춤 확인 → ready 대기.
  private func prepare(
    _ id: VirtualDevice.ID,
    attemptID: UUID,
    xcode: XcodeInstallation,
    key: String
  ) async throws(ScreenLayoutError) -> Session {
    // 시작하자마자 멈추기로 했으면(끄기·앱 종료의 `cancelAll` 이 먼저 지나감) 빌드를 새로 시작하지 않는다 (고아 xcodebuild 방지).
    try self.checkNotStopped(id, attemptID)
    let xctestrun = try await self.buildCache.xctestrun(key: key, xcode: xcode).get()
    try self.checkNotStopped(id, attemptID)
    let directory = self.sessionDirectory(id)
    await self.quitOrphanRunner(udid: id.rawValue, directory: directory)
    do {
      try? FileManager.default.removeItem(at: directory)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      throw .inspectorSetupFailed
    }
    // xcodebuild 는 꺼진 기기를 켠다. 켜져 있을 때만 띄운다.
    guard await self.isBooted(id) else { throw .deviceNotBooted }
    try self.checkNotStopped(id, attemptID)
    let token = UUID().uuidString
    let process: LaunchedProcess
    do throws(CommandError) {
      process = try await self.command.launch(
        LayoutRunnerCommands.xcodebuild(xcode),
        LayoutRunnerCommands.testArguments(xctestrun: xctestrun, udid: id.rawValue, sessionDirectory: directory),
        environment: LayoutRunnerCommands.testEnvironment(
          base: self.baseEnvironment,
          xcode: xcode,
          sessionDirectory: directory,
          token: token,
          idleSeconds: self.timing.idleSeconds
        )
      )
    } catch {
      throw error == .launchFailed ? .xcodeUnavailable : .inspectorSetupFailed
    }
    // launch 를 기다리는 사이 온 멈춤은 process 가 없어 SIGTERM 을 받지 못했다 → 기록한 바로 뒤 다시 본다.
    self.recordProcess(process, id, attemptID)
    try self.checkNotStopped(id, attemptID)
    let ready = try await self.waitForReady(
      id,
      attemptID: attemptID,
      process: process,
      directory: directory,
      token: token
    )
    return Session(
      deviceID: id,
      buildKey: key,
      token: token,
      process: process,
      runnerPID: ready.pid,
      scale: ready.scale,
      directory: directory
    )
  }

  /// ready.json(토큰 일치)을 `readyPollInterval` 마다 본다. xcodebuild 가 끝나거나 멈춤 요청이 오거나 `readyTimeout` 이 지나면
  /// `.inspectorSetupFailed`, `monitorInterval` 마다 목록을 읽어 그 기기가 켜져 있지 않으면 `.deviceNotBooted`
  /// (러너가 죽은 채 두면 xcodebuild 가 꺼진 기기를 다시 켠다, 실측). 프로세스는 부른 쪽이 멈춘다.
  private func waitForReady(
    _ id: VirtualDevice.ID,
    attemptID: UUID,
    process: LaunchedProcess,
    directory: URL,
    token: String
  ) async throws(ScreenLayoutError) -> LayoutRunnerProtocol.Ready {
    let readyURL = directory.appending(path: LayoutRunnerProtocol.readyFile)
    let clock = ContinuousClock()
    let start = clock.now
    var lastBootCheck = start
    while true {
      guard self.command.exitStatus(process) == nil else { throw .inspectorSetupFailed }
      try self.checkNotStopped(id, attemptID)
      if let data = try? Data(contentsOf: readyURL), let ready = LayoutRunnerProtocol.ready(from: data, token: token) {
        return ready
      }
      let now = clock.now
      guard now - start < self.timing.readyTimeout else { throw .inspectorSetupFailed }
      if now - lastBootCheck >= self.timing.monitorInterval {
        lastBootCheck = now
        guard await self.isBooted(id) else { throw .deviceNotBooted }
      }
      try? await Task.sleep(for: self.timing.readyPollInterval)
    }
  }

  /// 아직 이 Attempt 면 그 값.
  func attempt(_ id: VirtualDevice.ID, _ attemptID: UUID) -> Attempt? {
    guard case let .preparing(attempt) = self.runners[id], attempt.id == attemptID else { return nil }
    return attempt
  }

  private func checkNotStopped(_ id: VirtualDevice.ID, _ attemptID: UUID) throws(ScreenLayoutError) {
    guard let attempt = self.attempt(id, attemptID), !attempt.stopRequested else { throw .inspectorSetupFailed }
  }

  private func recordProcess(_ process: LaunchedProcess, _ id: VirtualDevice.ID, _ attemptID: UUID) {
    guard var attempt = self.attempt(id, attemptID) else { return }
    attempt.process = process
    self.runners[id] = .preparing(attempt)
  }
}
