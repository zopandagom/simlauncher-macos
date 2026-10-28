import CommandInterface
import Foundation
import Testing
@testable import CommandImpl

/// `launch`·`waitForExit`·`exitStatus`·`interrupt`. 실제 `/bin/sh` 를 실행한다.
struct CommandClientImplLaunchTests {
  @Test("launch 는 프로세스가 끝나기 전에 돌아오고, 도는 동안 exitStatus 는 nil")
  func returnsBeforeExit() async throws {
    let client = CommandClientImpl()
    let start = ContinuousClock.now

    let process = try await client.launch(Shell.shell, ["-c", "sleep 5"], environment: [:])

    #expect(ContinuousClock.now - start < .seconds(1))
    #expect(client.exitStatus(process) == nil)
    client.interrupt(process)
    _ = await client.waitForExit(process)
  }

  @Test("waitForExit 는 종료 코드를 돌려주고, 끝난 뒤 exitStatus·다시 부른 waitForExit 도 같은 값")
  func returnsExitCode() async throws {
    let client = CommandClientImpl()
    let process = try await client.launch(Shell.shell, ["-c", "exit 7"], environment: [:])

    let status = await client.waitForExit(process)

    #expect(status == 7)
    #expect(client.exitStatus(process) == 7)
    #expect(await client.waitForExit(process) == 7)
  }

  @Test("신호로 끝나면 128+신호 번호")
  func signalStatus() async throws {
    let client = CommandClientImpl()
    let process = try await client.launch(URL(filePath: "/bin/sleep"), ["5"], environment: [:])

    client.interrupt(process)

    #expect(await client.waitForExit(process) == 128 + SIGINT)
  }

  @Test("interrupt 는 SIGINT 를 보낸다 (INT 를 잡아 3 으로 끝나는 스크립트)")
  func interruptSendsSIGINT() async throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let script = """
    trap 'exit 3' INT
    echo $$ > \(scratch.quoted(scratch.pid))
    while :; do sleep 0.05; done
    """
    let client = CommandClientImpl()
    let process = try await client.launch(Shell.shell, ["-c", script], environment: [:])
    _ = try await scratch.waitForPID()

    client.interrupt(process)

    #expect(await client.waitForExit(process) == 3)
  }

  @Test("끝난 뒤의 interrupt 는 아무것도 하지 않는다")
  func interruptAfterExit() async throws {
    let client = CommandClientImpl()
    let process = try await client.launch(Shell.shell, ["-c", "exit 0"], environment: [:])
    #expect(await client.waitForExit(process) == 0)

    client.interrupt(process)

    #expect(client.exitStatus(process) == 0)
    #expect(await client.waitForExit(process) == 0)
  }

  @Test("waitForExit 를 부른 Task 를 취소하면 nil 로 돌아오고 프로세스는 계속 산다")
  func cancelledWaitLeavesProcess() async throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let script = """
    echo $$ > \(scratch.quoted(scratch.pid))
    while :; do sleep 0.05; done
    """
    let client = CommandClientImpl()
    let process = try await client.launch(Shell.shell, ["-c", script], environment: [:])
    let pid = try await scratch.waitForPID()
    let waiting = Task { await client.waitForExit(process) }

    waiting.cancel()

    #expect(await waiting.value == nil)
    #expect(client.exitStatus(process) == nil)
    #expect(Scratch.isAlive(pid))
    client.interrupt(process)
    #expect(await client.waitForExit(process) == 128 + SIGINT)
  }

  @Test("이미 취소된 Task 의 waitForExit 도 nil 이다")
  func alreadyCancelledWait() async throws {
    let client = CommandClientImpl()
    let process = try await client.launch(URL(filePath: "/bin/sleep"), ["5"], environment: [:])
    let waiting = Task {
      while !Task.isCancelled {
        await Task.yield()
      }
      return await client.waitForExit(process)
    }

    waiting.cancel()

    #expect(await waiting.value == nil)
    client.interrupt(process)
    _ = await client.waitForExit(process)
  }

  @Test("stdout 에 1 MiB 를 쓰는 자식도 막히지 않고 끝난다 (출력은 /dev/null)")
  func largeOutputDoesNotBlock() async throws {
    let client = CommandClientImpl()
    let start = ContinuousClock.now
    let process = try await client.launch(
      URL(filePath: "/usr/bin/head"),
      ["-c", "1048576", "/dev/zero"],
      environment: [:]
    )

    let status = await client.waitForExit(process)

    #expect(status == 0)
    #expect(ContinuousClock.now - start < .seconds(5))
  }

  @Test("없는 실행 파일은 launchFailed 를 던진다")
  func missingExecutableThrows() async {
    await #expect(throws: CommandError.launchFailed) {
      try await CommandClientImpl().launch(URL(filePath: "/nonexistent/tool"), [], environment: [:])
    }
  }

  @Test("띄우지 않은 값은 끝난 것으로 본다 (-1), interrupt 는 아무것도 하지 않는다")
  func unknownProcess() async {
    let client = CommandClientImpl()
    let unknown = LaunchedProcess(id: UUID())

    client.interrupt(unknown)

    #expect(client.exitStatus(unknown) == -1)
    #expect(await client.waitForExit(unknown) == -1)
  }

  @Test("Impl 복사본끼리 같은 표를 쓴다")
  func copiesShareTable() async throws {
    let client = CommandClientImpl()
    let copy = client
    let process = try await client.launch(Shell.shell, ["-c", "exit 4"], environment: [:])

    #expect(await copy.waitForExit(process) == 4)
    #expect(CommandClientImpl().exitStatus(process) == -1)
  }

  @Test("environment 를 그대로 프로세스 환경으로 쓴다")
  func usesEnvironment() async throws {
    let client = CommandClientImpl()
    let process = try await client.launch(
      Shell.shell,
      ["-c", #"[ "$K" = "v" ] && [ -z "$HOME" ] && exit 5; exit 6"#],
      environment: ["K": "v"]
    )

    #expect(await client.waitForExit(process) == 5)
  }
}
