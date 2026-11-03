import CommandInterface
import Foundation
import Synchronization
import Testing
@testable import CommandImpl

/// `streamCancellable`: stdout 을 쌓지 않는 실행. 실제 `/bin/sh` 를 실행한다.
struct CommandClientImplStreamCancellableTests {
  private static func stream(
    _ client: CommandClientImpl,
    _ script: String,
    log: OutputLog = OutputLog()
  ) async throws(CommandError) -> StreamedCommandResult {
    try await client.streamCancellable(Shell.shell, ["-c", script], environment: [:]) { output in
      log.append(output)
    }
  }

  @Test("조각을 순서대로 넘기고 결과에는 stdout 이 없다 (64KB 넘게 써도 멈추지 않는다)")
  func deliversWithoutRetainingStdout() async throws {
    let log = OutputLog()

    let result = try await Self.stream(
      Shell.client(),
      "printf a; sleep 0.2; printf b; head -c 200000 /dev/zero",
      log: log
    )

    #expect(result.exitCode == 0)
    #expect(result.stderr.isEmpty)
    #expect(log.chunks.first == .stdout(Data("a".utf8)))
    #expect(log.stdout.count == 200_002)
    #expect(log.stdout.prefix(2) == Data("ab".utf8))
  }

  @Test("stderr 는 앞 64 KiB 만 결과에 쌓고 조각은 모두 넘긴다, 종료 코드는 결과로")
  func stderrPrefixOnly() async throws {
    let log = OutputLog()

    let result = try await Self.stream(Shell.client(), "printf err >&2; head -c 100000 /dev/zero >&2; exit 4", log: log)

    #expect(result.exitCode == 4)
    #expect(result.stderr.count == StreamedCommandResult.stderrLimit)
    #expect(result.stderr.prefix(3) == Data("err".utf8))
    #expect(log.stderr.count == 100_003)
  }

  @Test("Task 를 취소하면 SIGINT 를 보내고, 프로세스가 끝난 뒤 cancelled")
  func cancelSendsInterrupt() async throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let script = """
    trap 'echo int > \(scratch.quoted(scratch.mark)); exit 130' INT
    echo $$ > \(scratch.quoted(scratch.pid))
    while :; do echo tick; sleep 0.1; done
    """
    let client = Shell.client()
    let task = Task { try await Self.stream(client, script) }
    let pid = try await scratch.waitForPID()

    task.cancel()

    await #expect(throws: CommandError.cancelled) { try await task.value }
    #expect(scratch.markText == "int")
    #expect(!Scratch.isAlive(pid))
  }

  @Test("시작 전에 이미 취소됐으면 실행하지 않고 cancelled")
  func cancelledBeforeStart() async throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let client = Shell.client()
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await Self.stream(client, "echo ran > \(scratch.quoted(scratch.mark))")
    }

    await #expect(throws: CommandError.cancelled) { try await task.value }
    try await Task.sleep(for: .milliseconds(200))
    #expect(scratch.markText == nil)
  }

  @Test("실행 파일을 띄우지 못하면 launchFailed")
  func launchFailed() async {
    let client = Shell.client()

    await #expect(throws: CommandError.launchFailed) {
      try await client.streamCancellable(URL(filePath: "/nonexistent/simlauncher-tool"), [], environment: [:]) { _ in }
    }
  }
}
