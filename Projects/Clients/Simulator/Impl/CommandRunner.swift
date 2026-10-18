import Foundation
import Synchronization

/// 끝난 명령의 결과.
struct CommandResult: Sendable {
  let exitCode: Int32
  let stdout: Data
  let stderr: Data
}

/// 실행 파일을 인자 배열로 실행한다(셸을 거치지 않는다). 테스트는 stub 으로 바꾼다.
protocol CommandRunner: Sendable {
  /// 프로세스를 시작하지 못하면 throw 한다. 0 이 아닌 종료 코드는 throw 하지 않고 결과로 돌려준다.
  func run(_ executable: URL, _ arguments: [String], environment: [String: String]) async throws -> CommandResult
}

/// `Process` 로 실제 명령을 실행하는 `CommandRunner`. Task 취소는 프로세스에 전하지 않는다.
struct ProcessCommandRunner: CommandRunner {
  func run(_ executable: URL, _ arguments: [String], environment: [String: String]) async throws -> CommandResult {
    try await withCheckedThrowingContinuation { continuation in
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
          continuation.resume(throwing: error)
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
          returning: CommandResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderrBox.withLock { $0 }
          )
        )
      }
    }
  }
}
