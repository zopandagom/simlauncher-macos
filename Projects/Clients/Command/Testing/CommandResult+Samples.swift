import CommandInterface
import Foundation

/// 테스트가 함께 쓰는 결과 샘플.
public extension CommandResult {
  /// 종료 코드 0, stderr 없음.
  static func success(_ stdout: Data = Data()) -> CommandResult {
    CommandResult(exitCode: 0, stdout: stdout, stderr: Data())
  }

  /// stdout 없음, stderr 는 UTF-8.
  static func failure(_ exitCode: Int32, _ stderr: String) -> CommandResult {
    CommandResult(exitCode: exitCode, stdout: Data(), stderr: Data(stderr.utf8))
  }
}
