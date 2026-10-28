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

  /// 오래 사는 프로세스를 띄우고 곧바로 돌아온다 (끝날 때까지 기다리지 않는다). 셸을 거치지 않는다.
  /// stdin·stdout·stderr 는 /dev/null 이다 (출력을 읽지 않는다: 오래 켜 두면 파이프가 차 자식이 막히므로).
  /// 프로세스를 시작하지 못하면 `.launchFailed`. 이 앱이 끝나도 프로세스는 남는다 (앱은 아무것도 보내지 않는다).
  /// - Parameter environment: 프로세스 환경 전체. 물려받은 환경에 더하지 않는다.
  func launch(
    _ executable: URL,
    _ arguments: [String],
    environment: [String: String]
  ) async throws(CommandError) -> LaunchedProcess

  /// 프로세스가 끝나기를 기다려 종료 상태를 돌려준다 (정상 종료면 종료 코드, 신호면 128+신호 번호. 셸과 같다).
  /// 이미 끝났으면 바로 돌려준다. 여러 번·여러 곳에서 불러도 같은 값. 부른 Task 가 취소되면 nil 로 돌아오고 프로세스는 건드리지 않는다.
  /// 이 Client 가 띄우지 않은 값이면 곧바로 -1 (끝난 것으로 본다).
  func waitForExit(_ process: LaunchedProcess) async -> Int32?

  /// 기다리지 않고 지금 종료 상태를 돌려준다. 아직 돌고 있으면 nil (`waitForExit` 와 같은 값 규칙).
  func exitStatus(_ process: LaunchedProcess) -> Int32?

  /// 아직 끝나지 않았으면 SIGINT 를 한 번 보낸다. 끝난 뒤(종료 처리 뒤)거나 이 Client 가 띄우지 않은 값이면 아무것도 하지 않는다.
  /// 끝날 때까지 기다리지 않는다 (`waitForExit` 로 기다린다).
  func interrupt(_ process: LaunchedProcess)
}
