import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation

// MARK: - 켜진 기기의 화면 캡처

public extension AndroidEmulatorClientImpl {
  /// 사전 확인(앱 작업과 같다) → `exec-out 'screencap -p 2>/dev/null'` → PNG 확인 → 예약 파일에 쓰기.
  @concurrent
  func screenshot(on id: AndroidVirtualDevice.ID, to file: URL) async throws(AndroidEmulatorError) {
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let serial = try await self.bootedSerial(id, tools: tools)
    let result = try await self.runApp(
      ADBCaptureCommands.screenshotArguments(serial: serial),
      tools: tools,
      timeout: self.timing.screenshotTimeout,
      timedOut: .captureFailed
    )
    guard result.exitCode == 0, ADBCaptureCommands.isPNG(result.stdout) else {
      throw .captureFailed
    }
    try CaptureFile.write(result.stdout, to: file)
  }

  /// 사전 확인·API 수준 → 남은 기기 임시 파일 정리 → 녹화 adb(비구조 Task, 제한 없음) → 멈춤 요청이나 스스로 끝나기를 기다림
  /// → 멈춤·가져오기·정리(취소를 물려받지 않는 Task). 사전 확인 도중 취소되면 멈출 프로세스가 없으므로 `.stoppedBeforeStart`.
  @concurrent
  func recordScreen(
    on id: AndroidVirtualDevice.ID,
    to file: URL,
    onStarted: @escaping @Sendable () async -> Void
  ) async throws(AndroidEmulatorError) -> AndroidScreenRecordingResult {
    let tools: SDKTools
    let serial: String
    let apiLevel: Int
    do throws(AndroidEmulatorError) {
      guard !Task.isCancelled else { return .stoppedBeforeStart }
      tools = try await SDKTools.resolve(self.sdkRoot())
      serial = try await self.bootedSerial(id, tools: tools)
      let arguments = ADBAppCommands.traitsArguments(serial: serial).apiLevel
      apiLevel = try await ADBAppCommands.parseAPILevel(self.runApp(arguments, tools: tools)).get()
      _ = try? await self.runApp(ADBCaptureCommands.cleanupArguments(serial: serial), tools: tools)
    } catch {
      // 취소된 Task 에서는 adb 가 실행되지 않아 다른 실패처럼 보일 수 있다.
      if Task.isCancelled {
        return .stoppedBeforeStart
      }
      throw error
    }
    guard !Task.isCancelled else { return .stoppedBeforeStart }
    let remote = ADBCaptureCommands.recordingPath(id: UUID())
    let session = RecordingSession()
    let arguments = ADBCaptureCommands.recordArguments(serial: serial, path: remote, apiLevel: apiLevel)
    let recorder = self.startRecorder(tools: tools, arguments: arguments, session: session, onStarted: onStarted)
    await withTaskCancellationHandler {
      await session.waitForStopOrEnd()
    } onCancel: {
      session.requestStop()
    }
    let target = RecordingTarget(
      serial: serial,
      remote: remote,
      file: file,
      timeLimited: apiLevel < ADBCaptureCommands.unlimitedAPILevel
    )
    // 취소된 Task 에서 runCancellable 은 실행하지 않으므로 멈춘 뒤의 명령은 취소를 물려받지 않는 Task 에서 돈다.
    let decision = await Task {
      await self.finishRecording(recorder, session: session, target: target, tools: tools)
    }.value
    session.markReturned()
    return try decision.result.get()
  }
}

/// 녹화 하나의 기기·파일.
struct RecordingTarget: Sendable {
  let serial: String
  let remote: String
  let file: URL
  /// API 34 아래라 기본 3분 제한으로 시작했다.
  let timeLimited: Bool
}

extension AndroidEmulatorClientImpl {
  /// 멈춤 → 가져오기(실패면 로컬을 0바이트로) → 판정 → (화면을 가져왔거나 없을 때만) 기기 임시 파일 지우기.
  func finishRecording(
    _ recorder: Task<Result<CommandResult, CommandError>, Never>,
    session: RecordingSession,
    target: RecordingTarget,
    tools: SDKTools
  ) async -> ADBRecordingOutcome.Decision {
    let ending = await self.stopRecording(recorder, session: session, serial: target.serial, tools: tools)
    let pull: ADBPullOutcome = if ending == .launchFailed {
      .remoteMissing
    } else {
      await self.pullRecording(target, tools: tools)
    }
    if case .pulled = pull {} else {
      // 일부만 받은 파일을 남기지 않는다 (원본은 기기에 남거나 없다). 호출한 쪽이 0바이트 파일을 지운다.
      CaptureFile.truncate(target.file)
    }
    let decision = ADBRecordingOutcome.decide(
      ending,
      timeLimited: target.timeLimited,
      sawStart: session.pid != nil,
      pull: pull
    )
    if decision.removesRemote {
      _ = try? await self.runApp(
        ADBCaptureCommands.removeArguments(serial: target.serial, remote: target.remote),
        tools: tools
      )
    }
    return decision
  }

  /// 멈춤 요청이 왔고 녹화 adb 가 아직 돌면: pid 를 알면 기기 안 `kill -2` 뒤 끝나기를 `recordingStopLimit` 까지 기다리고,
  /// 넘거나 pid 를 모르면 호스트에서 대신 멈춰 끝날 때까지 기다린다(pid 를 알았으면 기기 쪽 마무리를 `recordingSettle` 더 기다린다).
  /// 이미 끝났으면 `kill` 을 보내지 않는다 (pid 재사용 방지).
  private func stopRecording(
    _ recorder: Task<Result<CommandResult, CommandError>, Never>,
    session: RecordingSession,
    serial: String,
    tools: SDKTools
  ) async -> ADBRecordingOutcome.Ending {
    guard session.stopRequested, !session.hasEnded else {
      return await Self.ending(recorder.value, stopped: false)
    }
    if let pid = session.pid {
      _ = try? await self.runApp(ADBCaptureCommands.stopArguments(serial: serial, pid: pid), tools: tools)
      if await session.waitForEnd(limit: self.timing.recordingStopLimit) {
        return await Self.ending(recorder.value, stopped: true)
      }
      recorder.cancel()
      _ = await recorder.value
      try? await Task.sleep(for: self.timing.recordingSettle)
    } else {
      recorder.cancel()
      _ = await recorder.value
    }
    return .stoppedByHost
  }

  private func startRecorder(
    tools: SDKTools,
    arguments: [String],
    session: RecordingSession,
    onStarted: @escaping @Sendable () async -> Void
  ) -> Task<Result<CommandResult, CommandError>, Never> {
    let command = self.command
    let environment = ADBCommand.environment(home: self.home)
    return Task { () -> Result<CommandResult, CommandError> in
      defer { session.markEnded() }
      do throws(CommandError) {
        return try await .success(command.runCancellable(tools.adb, arguments, environment: environment, timeout: nil) {
          guard case let .stdout(data) = $0 else { return }
          if session.feed(data) {
            await onStarted()
          }
        })
      } catch {
        return .failure(error)
      }
    }
  }

  private static func ending(_ result: Result<CommandResult, CommandError>, stopped: Bool) -> ADBRecordingOutcome
    .Ending
  {
    switch result {
    case let .success(result):
      if stopped {
        .stopped(exitCode: result.exitCode)
      } else if ADBCaptureCommands.isDisplayOff(result) {
        .displayOff(code: result.exitCode)
      } else {
        .exited(code: result.exitCode)
      }
    case .failure(.launchFailed): .launchFailed
    // 녹화 adb 는 제한이 없고 이 앱이 취소할 때만 멈춘다.
    case .failure(.cancelled), .failure(.timedOut): .stoppedByHost
    }
  }

  /// `adb pull` (`transferTimeout`). 원인을 출력으로 가를 수 없는 실패는 `adb devices` 로 그 serial 이 online 인지 본다.
  private func pullRecording(_ target: RecordingTarget, tools: SDKTools) async -> ADBPullOutcome {
    let result: Result<CommandResult, CommandError>
    do throws(CommandError) {
      result = try await .success(self.command.runCancellable(
        tools.adb,
        ADBCaptureCommands.pullArguments(serial: target.serial, remote: target.remote, local: target.file),
        environment: ADBCommand.environment(home: self.home),
        timeout: self.timing.transferTimeout,
        onOutput: { _ in }
      ))
    } catch {
      result = .failure(error)
    }
    if let outcome = ADBPullOutcome.immediate(result, localSize: { CaptureFile.size(target.file) }) {
      return outcome
    }
    let devices = try? await self.adb(tools).devices()
    return ADBPullOutcome
      .afterDeviceCheck(online: devices?.contains { $0.serial == target.serial && $0.isOnline } ?? false)
  }
}
