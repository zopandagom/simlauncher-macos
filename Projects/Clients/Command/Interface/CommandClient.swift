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
}
