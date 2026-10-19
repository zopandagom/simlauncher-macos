import CommandInterface
import Foundation
import Synchronization

/// 테스트용 `CommandClient`. 실행 요청을 기록하고, 받은 처리기로 결과를 정한다.
public final class CommandClientFake: CommandClient {
  public struct Invocation: Hashable, Sendable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]

    public init(executable: URL, arguments: [String], environment: [String: String]) {
      self.executable = executable
      self.arguments = arguments
      self.environment = environment
    }
  }

  private let handler: @Sendable (Invocation) throws(CommandError) -> CommandResult
  private let recorded = Mutex<[Invocation]>([])

  public init(handler: @escaping @Sendable (Invocation) throws(CommandError) -> CommandResult) {
    self.handler = handler
  }

  /// 받은 요청, 순서대로.
  public var invocations: [Invocation] {
    self.recorded.withLock { $0 }
  }

  public func run(
    _ executable: URL,
    _ arguments: [String],
    environment: [String: String]
  ) async throws(CommandError) -> CommandResult {
    let invocation = Invocation(executable: executable, arguments: arguments, environment: environment)
    self.recorded.withLock { $0.append(invocation) }
    return try self.handler(invocation)
  }
}
