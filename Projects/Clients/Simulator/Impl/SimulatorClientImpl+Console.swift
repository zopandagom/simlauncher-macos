import CommandInterface
import Core
import Foundation
import SimulatorInterface
import Synchronization

// MARK: - 콘솔을 붙인 실행

public extension SimulatorClientImpl {
  /// 시간 제한 없이 `streamCancellable` 로 실행한다 (stdout 은 쌓지 않는다). stdout 만 파서에 넣고, stderr 는 결과의 앞부분으로 분류한다
  /// (실패 오류는 stderr 에만 온다, 측정). 알림은 lock 밖에서 기다린다 (다음 조각은 앞 알림이 끝난 뒤).
  /// 멈춘(취소) 뒤 남은 조각은 넘기지 않는다.
  func launchWithConsole(
    _ bundleID: AppBundleID,
    on id: VirtualDevice.ID,
    onEvent: @escaping @Sendable (AppConsoleEvent) async -> Void
  ) async throws(SimulatorError) -> AppConsoleEnd {
    guard let udid = SimctlCommand.validatedUDID(id.rawValue) else {
      throw .deviceNotFound
    }
    let directory = try await self.resolveDeveloperDirectory()
    let parser = ConsoleParserBox(bundleID: bundleID)
    let result: StreamedCommandResult
    do throws(CommandError) {
      result = try await self.command.streamCancellable(
        SimctlCommand.xcrun,
        SimctlCommand.launchWithConsole(udid: udid, bundleID: bundleID.rawValue),
        environment: SimctlCommand.consoleEnvironment(base: self.baseEnvironment, developerDirectory: directory)
      ) { output in
        guard case let .stdout(data) = output else { return }
        let events = parser.state.withLock { $0.feed(data) }
        for event in events {
          await onEvent(event)
        }
      }
    } catch {
      switch error {
      case .cancelled: return .stopped
      case .launchFailed: throw .developerToolsUnavailable
      // 시간 제한을 주지 않아 오지 않는다.
      case .timedOut: throw .commandFailed
      }
    }
    // 신호 전 실패는 stdout 이 비어 있다 (측정). 남은 조각을 넘기기 전에 판정해 실패에 `.launched` 가 섞이지 않게 한다.
    guard parser.state.withLock({ $0.hasLaunched }) || result.exitCode == 0 else {
      throw SimctlErrorClassifier.launchError(exitCode: result.exitCode, stderr: Self.stderr(result.stderr))
    }
    for event in parser.state.withLock({ $0.finish() }) {
      await onEvent(event)
    }
    return .exited
  }
}

/// 파서 상태. 출력 전달 클로저(@Sendable)가 바꾸므로 lock 으로 감싼다.
private final class ConsoleParserBox: Sendable {
  let state: Mutex<SimctlConsoleParser>

  init(bundleID: AppBundleID) {
    self.state = Mutex(SimctlConsoleParser(bundleID: bundleID))
  }
}
