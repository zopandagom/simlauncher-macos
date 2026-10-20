import CommandInterface
import Foundation
import Synchronization

/// 테스트용 `CommandClient`. 실행 요청을 기록하고, 받은 처리기로 결과를 정한다.
public final class CommandClientFake: CommandClient {
  public struct Invocation: Hashable, Sendable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
    /// `runCancellable` 로 왔으면 true.
    public let isCancellable: Bool
    /// `runCancellable` 의 시간 제한. `run` 이면 nil.
    public let timeout: Duration?

    /// 기존 3-인자 비교는 `run` 요청(false·nil)과 같다.
    public init(
      executable: URL,
      arguments: [String],
      environment: [String: String],
      isCancellable: Bool = false,
      timeout: Duration? = nil
    ) {
      self.executable = executable
      self.arguments = arguments
      self.environment = environment
      self.isCancellable = isCancellable
      self.timeout = timeout
    }
  }

  /// `runCancellable` 처리기. `emit` 으로 출력 조각을 넘기고(호출한 쪽의 `onOutput` 이 끝난 뒤 돌아온다) 결과를 정한다.
  public typealias CancellableHandler = @Sendable (
    Invocation,
    _ emit: @Sendable (CommandOutput) async -> Void
  ) async throws(CommandError) -> CommandResult

  private let handler: @Sendable (Invocation) throws(CommandError) -> CommandResult
  private let cancellableHandler: CancellableHandler?
  private let recorded = Mutex<[Invocation]>([])

  /// - Parameter cancellableHandler: `runCancellable` 처리기. nil 이면 `handler` 결과의 stdout·stderr 를
  ///   (비어 있지 않으면) 한 조각씩 넘기고 그 결과를 돌려준다. 넘기는 중 취소되면 남은 조각은 넘기지 않는다. 취소 흉내는 처리기가 `Task.sleep` 의 취소를 잡아
  ///   `.cancelled` 를 던지는 식으로 한다.
  public init(
    handler: @escaping @Sendable (Invocation) throws(CommandError) -> CommandResult,
    cancellableHandler: CancellableHandler? = nil
  ) {
    self.handler = handler
    self.cancellableHandler = cancellableHandler
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

  /// 먼저 요청을 기록하고, Task 가 이미 취소됐으면 처리기를 부르지 않고 `.cancelled` 를 던진다
  /// (Impl 의 "시작 전 취소면 실행하지 않음"과 같다).
  public func runCancellable(
    _ executable: URL,
    _ arguments: [String],
    environment: [String: String],
    timeout: Duration?,
    onOutput: @escaping @Sendable (CommandOutput) async -> Void
  ) async throws(CommandError) -> CommandResult {
    let invocation = Invocation(
      executable: executable,
      arguments: arguments,
      environment: environment,
      isCancellable: true,
      timeout: timeout
    )
    self.recorded.withLock { $0.append(invocation) }
    guard !Task.isCancelled else {
      throw .cancelled
    }
    if let cancellableHandler = self.cancellableHandler {
      return try await cancellableHandler(invocation, onOutput)
    }
    // 스스로 끝난 프로세스처럼: 넘기는 중 취소되면 남은 조각은 넘기지 않고 결과는 돌려준다 (Impl 과 같다).
    let result = try self.handler(invocation)
    if !result.stdout.isEmpty, !Task.isCancelled {
      await onOutput(.stdout(result.stdout))
    }
    if !result.stderr.isEmpty, !Task.isCancelled {
      await onOutput(.stderr(result.stderr))
    }
    return result
  }
}
