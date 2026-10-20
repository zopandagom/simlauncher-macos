import Foundation

/// 끝난 명령의 결과.
public struct CommandResult: Sendable {
  public let exitCode: Int32
  public let stdout: Data
  public let stderr: Data

  public init(exitCode: Int32, stdout: Data, stderr: Data) {
    self.exitCode = exitCode
    self.stdout = stdout
    self.stderr = stderr
  }
}

/// 실행 파일을 인자 배열로 실행한다(셸을 거치지 않는다). 인자 구성·결과 해석은 이것을 조합하는 Client Impl 이 한다.
public protocol CommandClient: Sendable {
  /// stdin 은 비우고, 끝날 때까지 기다려 stdout·stderr 를 끝까지 읽는다. Task 취소는 프로세스에 전하지 않는다.
  /// 프로세스를 시작하지 못할 때만 `.launchFailed` 를 던지고, 0 이 아닌 종료 코드는 결과로 돌려준다.
  /// - Parameter environment: 프로세스 환경 전체. 물려받은 환경에 더하지 않는다.
  func run(
    _ executable: URL,
    _ arguments: [String],
    environment: [String: String]
  ) async throws(CommandError) -> CommandResult

  /// stdin 은 비우고, 출력 조각을 받은 순서대로(stdout·stderr 각각 안에서) `onOutput` 에 넘기며 실행한다.
  /// 앞 조각의 `onOutput` 이 끝난 뒤 다음 조각을 넘긴다. 정상 종료면 모든 조각을 넘긴 뒤 전체 stdout·stderr 를 결과로 돌려준다.
  /// 프로세스가 스스로 끝난 뒤 취소가 오면 결과(전체 출력)를 돌려주되, 일부 조각은 `onOutput` 에 넘기지 않았을 수 있다.
  /// 돌아온 뒤에는 `onOutput` 을 부르지 않는다.
  /// Task 가 취소되거나 `timeout` 이 지나면 SIGINT → (10초) SIGTERM → (5초) SIGKILL 순서로 멈추고,
  /// **프로세스가 끝난 뒤** `.cancelled`·`.timedOut` 을 던진다 (둘이 겹치면 먼저 온 것). 멈추기로 한 뒤의 출력은 넘기지 않을 수 있다.
  /// 멈추기 전에 프로세스가 스스로 끝났으면 결과를 돌려준다. 시작 전에 이미 취소됐으면 실행하지 않고 `.cancelled`.
  /// 프로세스를 시작하지 못하면 `.launchFailed`, 0 이 아닌 종료 코드는 결과로 돌려준다.
  /// - Parameter environment: 프로세스 환경 전체. 물려받은 환경에 더하지 않는다.
  /// - Parameter timeout: nil 이면 제한 없음.
  func runCancellable(
    _ executable: URL,
    _ arguments: [String],
    environment: [String: String],
    timeout: Duration?,
    onOutput: @escaping @Sendable (CommandOutput) async -> Void
  ) async throws(CommandError) -> CommandResult
}
