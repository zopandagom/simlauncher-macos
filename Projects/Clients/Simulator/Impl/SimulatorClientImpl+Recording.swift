import CommandInterface
import Core
import Foundation
import SimulatorInterface
import Synchronization

// MARK: - 녹화

public extension SimulatorClientImpl {
  /// 같은 디렉터리로 목록을 다시 읽어 켜진 기기일 때만 실행한다 (꺼진 기기에서는 simctl 이 0바이트 파일을 남기고 성공한다).
  /// 목록 확인은 취소를 보지 않고, 그 뒤 `runCancellable` 이 이미 취소됐으면 실행하지 않는다 (→ `.stoppedBeforeStart`).
  /// 시간 제한은 두지 않는다 (사용자가 멈출 때까지). 멈춤은 Command 의 표준 단계(SIGINT → 10초 SIGTERM → 5초 SIGKILL)를 따른다.
  /// 결과는 종료 코드 대신 시작 신호와 끝난 뒤 파일 크기로 정한다 (`SimctlRecordingOutcome`).
  /// 화면을 고르지 않아 시작 전에 실패하면(화면이 둘인 iPhone Duo, `SimctlCommand.needsDisplay`) 기본 화면을 골라 한 번 더 띄운다.
  func recordVideo(
    on id: VirtualDevice.ID,
    to file: URL,
    onStarted: @escaping @Sendable () async -> Void
  ) async throws(SimulatorError) -> ScreenRecordingResult {
    guard let udid = SimctlCommand.validatedUDID(id.rawValue) else {
      throw .deviceNotFound
    }
    guard file.isFileURL else {
      throw .commandFailed
    }
    let directory = try await self.resolveDeveloperDirectory()
    try await self.requireBootedDevice(udid, developerDirectory: directory)
    let path = file.standardizedFileURL.path(percentEncoded: false)
    var attempt = await self.runRecording(
      udid: udid,
      path: path,
      display: nil,
      directory: directory,
      onStarted: onStarted
    )
    // 화면이 둘인 기기(iPhone Duo): 화면을 고르지 않으면 시작 전에 실패한다 → 기본 화면으로 한 번 더 (취소면 하지 않는다).
    if !attempt.sawStart, case let .exited(code, stderr) = attempt.ending,
       SimctlCommand.needsDisplay(exitCode: code, stderr: stderr), !Task.isCancelled
    {
      attempt = await self.runRecording(
        udid: udid,
        path: path,
        display: SimctlCommand.displayOption,
        directory: directory,
        onStarted: onStarted
      )
    }
    return try SimctlRecordingOutcome.decide(attempt.ending, sawStart: attempt.sawStart, fileSize: self.fileSize(file))
  }
}

extension SimulatorClientImpl {
  /// recordVideo 한 번: 끝난 방식과 시작 신호를 보았는지.
  private func runRecording(
    udid: String,
    path: String,
    display: String?,
    directory: URL?,
    onStarted: @escaping @Sendable () async -> Void
  ) async -> (ending: SimctlRecordingOutcome.Ending, sawStart: Bool) {
    let detector = DetectorBox()
    let environment = SimctlCommand.environment(base: self.baseEnvironment, developerDirectory: directory)
    let ending: SimctlRecordingOutcome.Ending
    do throws(CommandError) {
      let result = try await self.command.runCancellable(
        SimctlCommand.xcrun,
        SimctlCommand.recordVideo(udid: udid, path: path, display: display),
        environment: environment,
        timeout: nil
      ) { output in
        // stdout 에는 경로(기기 이름)가 섞이므로 stderr 만 본다. 신호는 lock 안에서 찾고, 알림은 lock 밖에서 기다린다.
        guard case let .stderr(data) = output else { return }
        if detector.state.withLock({ $0.feed(data) }) {
          await onStarted()
        }
      }
      ending = .exited(code: result.exitCode, stderr: Self.stderr(result))
    } catch {
      switch error {
      case .cancelled: ending = .stopped
      case .launchFailed: ending = .launchFailed
      case .timedOut: ending = .timedOut
      }
    }
    return (ending, detector.state.withLock { $0.sawStart })
  }
}

/// 시작 신호 감지기. 출력 전달 클로저(@Sendable)가 바꾸므로 lock 으로 감싼다.
private final class DetectorBox: Sendable {
  let state = Mutex(RecordingStartDetector())
}
