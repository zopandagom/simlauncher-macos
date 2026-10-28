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
    /// `launch` 로 왔으면 true.
    public let isLaunch: Bool

    /// 기존 3-인자 비교는 `run` 요청(false·nil)과 같다.
    public init(
      executable: URL,
      arguments: [String],
      environment: [String: String],
      isCancellable: Bool = false,
      timeout: Duration? = nil,
      isLaunch: Bool = false
    ) {
      self.executable = executable
      self.arguments = arguments
      self.environment = environment
      self.isCancellable = isCancellable
      self.timeout = timeout
      self.isLaunch = isLaunch
    }
  }

  /// `runCancellable` 처리기. `emit` 으로 출력 조각을 넘기고(호출한 쪽의 `onOutput` 이 끝난 뒤 돌아온다) 결과를 정한다.
  public typealias CancellableHandler = @Sendable (
    Invocation,
    _ emit: @Sendable (CommandOutput) async -> Void
  ) async throws(CommandError) -> CommandResult

  /// `launch` 처리기. 던지면 띄우지 못한 것이다. 아니면 프로세스는 `exit` 를 부를 때까지 돈다
  /// (테스트가 끝나는 시점과 종료 상태를 정한다. 처리기 안에서 바로 불러도 되고, 붙잡아 두었다가 나중에 불러도 된다).
  public typealias LaunchHandler = @Sendable (
    Invocation,
    LaunchedProcess,
    _ exit: @escaping @Sendable (Int32) -> Void
  ) throws(CommandError) -> Void

  /// 띄운 프로세스 하나. 끝나면 `status` 가 서고 기다리는 쪽을 깨운다.
  private struct LaunchedEntry {
    var status: Int32?
    var waiters: [UUID: CheckedContinuation<Int32?, Never>] = [:]
  }

  private let handler: @Sendable (Invocation) throws(CommandError) -> CommandResult
  private let cancellableHandler: CancellableHandler?
  private let launchHandler: LaunchHandler?
  private let interruptHandler: (@Sendable (LaunchedProcess) -> Void)?
  private let recorded = Mutex<[Invocation]>([])
  private let recordedInterrupts = Mutex<[LaunchedProcess]>([])
  private let launched = Mutex<[UUID: LaunchedEntry]>([:])

  /// - Parameter cancellableHandler: `runCancellable` 처리기. nil 이면 `handler` 결과의 stdout·stderr 를
  ///   (비어 있지 않으면) 한 조각씩 넘기고 그 결과를 돌려준다. 넘기는 중 취소되면 남은 조각은 넘기지 않는다. 취소 흉내는 처리기가 `Task.sleep` 의 취소를 잡아
  ///   `.cancelled` 를 던지는 식으로 한다.
  /// - Parameter launchHandler: `launch` 처리기. nil 이면 띄우기는 성공하고 프로세스는 `exit(_:status:)` 를 부를 때까지 돈다.
  /// - Parameter interruptHandler: 아직 끝나지 않은 프로세스에 `interrupt` 가 오면 부른다 (SIGINT 를 받고 끝나는 흉내는 여기서 `exit` 를 부른다).
  public init(
    handler: @escaping @Sendable (Invocation) throws(CommandError) -> CommandResult,
    cancellableHandler: CancellableHandler? = nil,
    launchHandler: LaunchHandler? = nil,
    interruptHandler: (@Sendable (LaunchedProcess) -> Void)? = nil
  ) {
    self.handler = handler
    self.cancellableHandler = cancellableHandler
    self.launchHandler = launchHandler
    self.interruptHandler = interruptHandler
  }

  /// 받은 요청, 순서대로.
  public var invocations: [Invocation] {
    self.recorded.withLock { $0 }
  }

  /// `interrupt` 로 받은 프로세스, 순서대로 (끝났거나 모르는 값도 기록한다).
  public var interrupts: [LaunchedProcess] {
    self.recordedInterrupts.withLock { $0 }
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

  /// 요청을 기록하고 `launchHandler` 로 결과를 정한다. 처리기가 던지면 표에 남기지 않는다.
  public func launch(
    _ executable: URL,
    _ arguments: [String],
    environment: [String: String]
  ) async throws(CommandError) -> LaunchedProcess {
    let invocation = Invocation(
      executable: executable,
      arguments: arguments,
      environment: environment,
      isLaunch: true
    )
    self.recorded.withLock { $0.append(invocation) }
    let process = LaunchedProcess(id: UUID())
    self.launched.withLock { $0[process.id] = LaunchedEntry() }
    do throws(CommandError) {
      try self.launchHandler?(invocation, process) { [weak self] status in
        self?.exit(process, status: status)
      }
    } catch {
      self.launched.withLock { _ = $0.removeValue(forKey: process.id) }
      throw error
    }
    return process
  }

  /// 띄운 프로세스를 끝낸다 (Impl 의 종료 처리와 같다). 이미 끝났거나 모르는 값이면 아무것도 하지 않는다.
  public func exit(_ process: LaunchedProcess, status: Int32) {
    let waiters = self.launched.withLock { entries -> [CheckedContinuation<Int32?, Never>] in
      guard var entry = entries[process.id], entry.status == nil else {
        return []
      }
      entry.status = status
      let waiters = Array(entry.waiters.values)
      entry.waiters = [:]
      entries[process.id] = entry
      return waiters
    }
    for waiter in waiters {
      waiter.resume(returning: status)
    }
  }

  /// Impl 과 같은 규칙: 이미 끝났으면 바로, 모르는 값이면 -1, 부른 Task 가 취소되면 nil.
  public func waitForExit(_ process: LaunchedProcess) async -> Int32? {
    let token = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Int32?, Never>) in
        let immediate: Int32?? = self.launched.withLock { entries in
          guard var entry = entries[process.id] else {
            return .some(-1)
          }
          if let status = entry.status {
            return .some(status)
          }
          if Task.isCancelled {
            return .some(nil)
          }
          entry.waiters[token] = continuation
          entries[process.id] = entry
          return nil
        }
        if let immediate {
          continuation.resume(returning: immediate)
        }
      }
    } onCancel: {
      let waiter = self.launched.withLock { entries -> CheckedContinuation<Int32?, Never>? in
        entries[process.id]?.waiters.removeValue(forKey: token)
      }
      waiter?.resume(returning: nil)
    }
  }

  /// 돌고 있으면 nil, 끝났으면 종료 상태, 모르는 값이면 -1.
  public func exitStatus(_ process: LaunchedProcess) -> Int32? {
    self.launched.withLock { entries in
      guard let entry = entries[process.id] else {
        return -1
      }
      return entry.status
    }
  }

  /// 기록하고, 아직 끝나지 않은 프로세스면 `interruptHandler` 를 부른다.
  public func interrupt(_ process: LaunchedProcess) {
    self.recordedInterrupts.withLock { $0.append(process) }
    let isRunning = self.launched.withLock { entries in
      entries[process.id].map { $0.status == nil } ?? false
    }
    if isRunning {
      self.interruptHandler?(process)
    }
  }
}
