import CommandInterface
import Foundation
import Synchronization
import Testing
@testable import CommandImpl

/// `runCancellable` 의 출력 전달과 시작. 실제 `/bin/sh` 를 실행한다.
struct CommandClientImplStreamingTests {
  // MARK: - 출력

  @Test("조각을 순서대로 넘기고 결과에 전체 stdout 을 담는다")
  func deliversChunksInOrder() async throws {
    let log = OutputLog()
    let result = try await Shell.run(Shell.client(), "printf a; sleep 0.2; printf b", log: log)

    #expect(result.exitCode == 0)
    #expect(result.stdout == Data("ab".utf8))
    #expect(log.stdout == Data("ab".utf8))
    #expect(log.chunks.first == .stdout(Data("a".utf8)))
    #expect(log.chunks.count >= 2)
  }

  @Test("stderr 조각은 .stderr 로 넘기고, 0 이 아닌 종료 코드는 결과로 돌려준다")
  func stderrAndExitCode() async throws {
    let log = OutputLog()
    let result = try await Shell.run(Shell.client(), "echo err >&2; exit 3", log: log)

    #expect(result.exitCode == 3)
    #expect(result.stderr == Data("err\n".utf8))
    #expect(result.stdout.isEmpty)
    #expect(log.stderr == Data("err\n".utf8))
    #expect(log.stdout.isEmpty)
  }

  @Test("파이프 버퍼(64KB)보다 큰 출력도 멈추지 않는다")
  func largeOutput() async throws {
    let log = OutputLog()
    let result = try await Shell.run(Shell.client(), "head -c 200000 /dev/zero", log: log)

    #expect(result.stdout.count == 200_000)
    #expect(log.stdout.count == 200_000)
  }

  @Test("stdout·stderr 둘 다 64KB 넘게 동시에 써도 멈추지 않고 결과에 전부 담는다")
  func largeOutputOnBothStreams() async throws {
    let log = OutputLog()
    let script = "head -c 200000 /dev/zero & head -c 300000 /dev/zero >&2; wait"
    let result = try await Shell.run(Shell.client(), script, log: log)

    #expect(result.stdout.count == 200_000)
    #expect(result.stderr.count == 300_000)
    #expect(log.stdout.count == 200_000)
    #expect(log.stderr.count == 300_000)
  }

  @Test("돌아온 뒤에는 onOutput 을 부르지 않는다")
  func noOutputAfterReturn() async throws {
    let log = OutputLog()
    _ = try await Shell.run(Shell.client(), "printf a; printf b >&2; printf c", log: log)
    let count = log.chunks.count

    try await Task.sleep(for: .milliseconds(300))

    #expect(log.chunks.count == count)
    #expect(log.stdout == Data("ac".utf8))
  }

  @Test("손자 프로세스가 파이프를 쥐어도 부모가 끝나면 eofGrace 안에 돌아온다")
  func grandchildHoldingPipe() async throws {
    let start = ContinuousClock.now
    let result = try await Shell.run(Shell.client(eofGrace: .milliseconds(300)), "sleep 30 & echo $!; echo hi")
    let elapsed = ContinuousClock.now - start
    let lines = (String(bytes: result.stdout, encoding: .utf8) ?? "").split(separator: "\n")
    defer { Scratch.kill(lines.first.flatMap { Int32($0) }) }

    #expect(result.exitCode == 0)
    #expect(lines.last == "hi")
    #expect(elapsed < .seconds(5))
  }

  // MARK: - 시작

  @Test("없는 실행 파일은 launchFailed")
  func missingExecutable() async {
    await #expect(throws: CommandError.launchFailed) {
      try await Shell.client().runCancellable(
        URL(filePath: "/nonexistent/tool"),
        [],
        environment: [:],
        timeout: nil
      ) { _ in }
    }
  }

  @Test("시작 전에 취소됐으면 실행하지 않고 cancelled")
  func cancelledBeforeStart() async throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let client = Shell.client()
    let script = "touch '\(scratch.mark.path(percentEncoded: false))'"

    let task = Task {
      while !Task.isCancelled {
        await Task.yield()
      }
      return try await Shell.run(client, script)
    }
    task.cancel()

    await #expect(throws: CommandError.cancelled) { try await task.value }
    try await Task.sleep(for: .milliseconds(300))
    #expect(!FileManager.default.fileExists(atPath: scratch.mark.path(percentEncoded: false)))
  }
}
