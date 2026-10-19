import CommandInterface
import Foundation
import Synchronization

/// `Process` 로 실제 명령을 실행하는 `CommandClient`.
public struct CommandClientImpl: CommandClient {
  public init() {}

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
}
