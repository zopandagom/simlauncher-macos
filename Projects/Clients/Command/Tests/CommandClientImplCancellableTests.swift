import CommandInterface
import Foundation
import Synchronization
import Testing
@testable import CommandImpl

/// `runCancellable` 의 취소·시간 제한·멈춤 단계. 실제 `/bin/sh` 를 실행한다.
struct CommandClientImplCancellableTests {
  // MARK: - 취소·시간 제한

  @Test("Task 를 취소하면 SIGINT 를 보내고, 프로세스가 끝난 뒤 cancelled")
  func cancelSendsInterrupt() async throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let script = """
    trap 'echo int > \(scratch.quoted(scratch.mark)); exit 130' INT
    sleep 30 >/dev/null 2>&1 &
    echo $! > \(scratch.quoted(scratch.child))
    echo $$ > \(scratch.quoted(scratch.pid))
    wait $!
    """
    let client = Shell.client()
    let task = Task { try await Shell.run(client, script) }
    let pid = try await scratch.waitForPID()

    task.cancel()

    await #expect(throws: CommandError.cancelled) { try await task.value }
    #expect(scratch.markText == "int")
    #expect(!Scratch.isAlive(pid))
  }

  @Test("SIGINT 를 무시하면 interruptGrace 뒤 SIGTERM")
  func interruptIgnoredThenTerminate() async throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let script = """
    trap '' INT
    trap 'echo term > \(scratch.quoted(scratch.mark)); exit 143' TERM
    sleep 30 >/dev/null 2>&1 &
    echo $! > \(scratch.quoted(scratch.child))
    echo $$ > \(scratch.quoted(scratch.pid))
    wait $!
    """
    let client = Shell.client(interruptGrace: .milliseconds(300))
    let task = Task { try await Shell.run(client, script) }
    let pid = try await scratch.waitForPID()

    task.cancel()

    await #expect(throws: CommandError.cancelled) { try await task.value }
    #expect(scratch.markText == "term")
    #expect(!Scratch.isAlive(pid))
  }

  @Test("SIGINT·SIGTERM 을 무시하면 SIGKILL, 손자가 파이프를 쥐어도 eofGrace 안에 돌아온다")
  func killAfterTerminateIgnored() async throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let script = """
    trap '' INT TERM
    sleep 30 &
    echo $! > \(scratch.quoted(scratch.child))
    echo $$ > \(scratch.quoted(scratch.pid))
    wait $!
    """
    let client = Shell.client(
      interruptGrace: .milliseconds(200),
      terminateGrace: .milliseconds(200),
      eofGrace: .milliseconds(300)
    )
    let task = Task { try await Shell.run(client, script) }
    let pid = try await scratch.waitForPID()
    let start = ContinuousClock.now

    task.cancel()

    await #expect(throws: CommandError.cancelled) { try await task.value }
    #expect(ContinuousClock.now - start < .seconds(5))
    #expect(!Scratch.isAlive(pid))
  }

  @Test("시간 제한이 지나면 멈추고, 프로세스가 끝난 뒤 timedOut")
  func timeout() async throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let script = "echo $$ > \(scratch.quoted(scratch.pid)); exec sleep 30"
    let client = Shell.client()
    let task = Task { try await Shell.run(client, script, timeout: .milliseconds(300)) }
    let pid = try await scratch.waitForPID()

    await #expect(throws: CommandError.timedOut) { try await task.value }
    #expect(!Scratch.isAlive(pid))
  }

  @Test("시간 제한 전에 끝나면 결과를 돌려준다")
  func finishesBeforeTimeout() async throws {
    let result = try await Shell.run(Shell.client(), "sleep 0.1; printf ok", timeout: .milliseconds(500))
    try await Task.sleep(for: .milliseconds(600))

    #expect(result.exitCode == 0)
    #expect(result.stdout == Data("ok".utf8))
  }

  @Test("시간 초과로 멈추는 중에 취소가 와도 먼저 온 이유(timedOut)")
  func firstReasonWins() async throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let script = """
    trap '' INT
    trap 'exit 143' TERM
    sleep 30 >/dev/null 2>&1 &
    echo $! > \(scratch.quoted(scratch.child))
    echo $$ > \(scratch.quoted(scratch.pid))
    wait $!
    """
    let client = Shell.client(interruptGrace: .seconds(1))
    let task = Task { try await Shell.run(client, script, timeout: .milliseconds(200)) }
    _ = try await scratch.waitForPID()
    try await Task.sleep(for: .milliseconds(500))

    task.cancel()

    await #expect(throws: CommandError.timedOut) { try await task.value }
  }

  @Test("느린 onOutput 중에 취소하면 프로세스를 멈추고 끝난 뒤 cancelled")
  func cancelDuringSlowOutput() async throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let script = """
    trap 'exit 130' INT
    echo $$ > \(scratch.quoted(scratch.pid))
    while :; do echo tick; sleep 0.1; done
    """
    let started = Mutex(false)
    let calls = Mutex(0)
    let client = Shell.client()
    let task = Task {
      try await client.runCancellable(Shell.shell, ["-c", script], environment: [:], timeout: nil) { _ in
        started.withLock { $0 = true }
        calls.withLock { $0 += 1 }
        await Scratch.uncancellableSleep(.milliseconds(500))
      }
    }
    let pid = try await scratch.waitForPID()
    try await Scratch.waitUntil { started.withLock { $0 } }

    task.cancel()

    await #expect(throws: CommandError.cancelled) { try await task.value }
    #expect(!Scratch.isAlive(pid))
    // 취소 뒤 쌓인 조각은 넘기지 않는다.
    #expect(calls.withLock { $0 } == 1)
  }

  @Test("프로세스가 스스로 끝난 뒤 느린 onOutput 중에 취소해도 결과 stdout 은 전부다")
  func cancelAfterExitKeepsFullOutput() async throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let script = """
    echo $$ > \(scratch.quoted(scratch.pid))
    printf a; sleep 0.1; printf b; sleep 0.1; printf c
    """
    let started = Mutex(false)
    let calls = Mutex(0)
    let client = Shell.client()
    let task = Task {
      try await client.runCancellable(Shell.shell, ["-c", script], environment: [:], timeout: nil) { _ in
        started.withLock { $0 = true }
        calls.withLock { $0 += 1 }
        await Scratch.uncancellableSleep(.seconds(1))
      }
    }
    let pid = try await scratch.waitForPID()
    try await Scratch.waitUntil { started.withLock { $0 } && !Scratch.isAlive(pid) }
    try await Task.sleep(for: .milliseconds(200))

    task.cancel()

    let result = try await task.value
    #expect(result.exitCode == 0)
    #expect(result.stdout == Data("abc".utf8))
    #expect(calls.withLock { $0 } == 1)
  }

  @Test("취소 뒤 자식이 64KB 넘게 쓰고 끝나도 파이프를 계속 읽어 SIGINT 단계에서 끝난다")
  func keepsReadingAfterStop() async throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let script = """
    trap 'head -c 200000 /dev/zero; echo done > \(scratch.quoted(scratch.mark)); exit 130' INT
    sleep 30 >/dev/null 2>&1 &
    echo $! > \(scratch.quoted(scratch.child))
    echo $$ > \(scratch.quoted(scratch.pid))
    wait $!
    """
    let client = Shell.client(interruptGrace: .seconds(5))
    let task = Task { try await Shell.run(client, script) }
    _ = try await scratch.waitForPID()
    let start = ContinuousClock.now

    task.cancel()

    await #expect(throws: CommandError.cancelled) { try await task.value }
    #expect(ContinuousClock.now - start < .seconds(4))
    #expect(scratch.markText == "done")
  }

  @Test("Duration 을 나노초 간격으로 바꾼다 (음수는 0, 아주 크면 never)")
  func dispatchInterval() {
    #expect(ProcessControl.dispatchInterval(.milliseconds(1500)) == .nanoseconds(1_500_000_000))
    #expect(ProcessControl.dispatchInterval(.seconds(30)) == .nanoseconds(30_000_000_000))
    #expect(ProcessControl.dispatchInterval(.seconds(-1)) == .nanoseconds(0))
    #expect(ProcessControl.dispatchInterval(.seconds(Int64(2_000_000_000))) == .never)
  }
}
