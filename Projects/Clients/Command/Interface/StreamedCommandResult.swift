import Foundation

/// `streamCancellable` 로 끝난 명령의 결과. stdout 은 쌓지 않는다 (조각으로만 넘긴다).
public struct StreamedCommandResult: Sendable {
  /// 결과에 쌓는 stderr 의 앞 바이트 수 (실패 분류용). 넘는 뒤쪽은 조각으로만 넘긴다.
  public static let stderrLimit = 64 * 1024

  public let exitCode: Int32
  /// stderr 의 앞 `stderrLimit` 바이트.
  public let stderr: Data

  public init(exitCode: Int32, stderr: Data) {
    self.exitCode = exitCode
    self.stderr = stderr
  }
}
