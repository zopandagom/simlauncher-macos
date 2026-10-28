import CommandInterface
import Foundation
import Synchronization

/// `Process` 로 실제 명령을 실행하는 `CommandClient`.
public struct CommandClientImpl: CommandClient {
  private let timing: ProcessControl.Timing
  /// `launch` 가 띄운 프로세스. 복사본끼리 같은 표를 쓴다.
  private let launchedProcesses = LaunchedProcessTable()

  public init() {
    self.timing = .standard
  }

  /// 테스트용: `runCancellable` 의 멈춤 단계 간격과 종료 뒤 EOF 대기 시간을 정한다.
  init(interruptGrace: Duration, terminateGrace: Duration, eofGrace: Duration) {
    self.timing = ProcessControl.Timing(
      interruptGrace: interruptGrace,
      terminateGrace: terminateGrace,
      eofGrace: eofGrace
    )
  }

  public func run(
    _ executable: URL,
    _ arguments: [String],
    environment: [String: String]
  ) async throws(CommandError) -> CommandResult {
    let result: Result<CommandResult, CommandError> = await withCheckedContinuation { continuation in
      // 블로킹 읽기·대기는 협력 스레드 풀 밖에서 한다.
      DispatchQueue.global().async {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
          try process.run()
        } catch {
          continuation.resume(returning: .failure(.launchFailed))
          return
        }
        // 출력이 파이프 버퍼(64KB)를 넘으면 자식이 쓰기에서 멈추므로,
        // 종료를 기다리기 전에 stdout·stderr 를 동시에 끝까지 읽는다.
        let stderrBox = Mutex<Data>(Data())
        let stderrHandle = stderrPipe.fileHandleForReading
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
          let data = stderrHandle.readDataToEndOfFile()
          stderrBox.withLock { $0 = data }
          group.leave()
        }
        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        continuation.resume(
          returning: .success(
            CommandResult(
              exitCode: process.terminationStatus,
              stdout: stdout,
              stderr: stderrBox.withLock { $0 }
            )
          )
        )
      }
    }
    return try result.get()
  }

  public func runCancellable(
    _ executable: URL,
    _ arguments: [String],
    environment: [String: String],
    timeout: Duration?,
    onOutput: @escaping @Sendable (CommandOutput) async -> Void
  ) async throws(CommandError) -> CommandResult {
    guard !Task.isCancelled else {
      throw .cancelled
    }
    let (stream, continuation) = AsyncStream<CommandOutput>.makeStream()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    let control = ProcessControl(
      timing: self.timing,
      stdout: stdoutPipe.fileHandleForReading,
      stderr: stderrPipe.fileHandleForReading,
      continuation: continuation
    )
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = environment
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    process.terminationHandler = { process in
      control.exited(process.terminationStatus)
    }

    let result: Result<CommandResult, CommandError> = await withTaskCancellationHandler {
      // 시작 전 취소 확인을 지난 뒤 온 취소는 시작 직후 SIGINT 로 처리한다 (`launched`).
      guard control.shouldLaunch() else {
        return .failure(.cancelled)
      }
      control.startReading()
      do {
        try process.run()
      } catch {
        control.stopReading()
        return .failure(.launchFailed)
      }
      control.launched(pid: process.processIdentifier)
      if let timeout {
        control.startTimer(timeout)
      }
      // 취소되면 남은 조각(스트림에 쌓인 것 포함)은 넘기지 않는다. 종료·EOF 는 취소와 무관하게 기다린다.
      for await output in stream {
        guard !Task.isCancelled else {
          break
        }
        await onOutput(output)
      }
      let exitCode = await control.waitForExit()
      await control.waitForOutputEnd()
      return control.outcome(exitCode: exitCode)
    } onCancel: {
      control.requestStop(.cancelled)
    }
    return try result.get()
  }

  public func launch(
    _ executable: URL,
    _ arguments: [String],
    environment: [String: String]
  ) async throws(CommandError) -> LaunchedProcess {
    let id = UUID()
    let table = self.launchedProcesses
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = environment
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.terminationHandler = { process in
      table.exited(id, status: Self.exitStatus(of: process))
    }
    table.register(id)
    do {
      try process.run()
    } catch {
      table.discard(id)
      throw .launchFailed
    }
    table.launched(id, process: process)
    return LaunchedProcess(id: id)
  }

  public func waitForExit(_ process: LaunchedProcess) async -> Int32? {
    await self.launchedProcesses.wait(process.id)
  }

  public func exitStatus(_ process: LaunchedProcess) -> Int32? {
    self.launchedProcesses.status(process.id)
  }

  public func interrupt(_ process: LaunchedProcess) {
    self.launchedProcesses.interrupt(process.id)
  }

  /// 정상 종료면 종료 코드, 신호로 끝났으면 128+신호 번호 (셸과 같다).
  private static func exitStatus(of process: Process) -> Int32 {
    switch process.terminationReason {
    case .exit: process.terminationStatus
    case .uncaughtSignal: 128 + process.terminationStatus
    @unknown default: process.terminationStatus
    }
  }
}
