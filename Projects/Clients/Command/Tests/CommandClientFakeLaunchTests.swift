import CommandInterface
import CommandTesting
import Foundation
import Synchronization
import Testing

struct CommandClientFakeLaunchTests {
  private static let tool = URL(filePath: "/usr/bin/tool")

  @Test("launch 는 isLaunch 로 기록하고, 처리기가 없으면 exit 를 부를 때까지 돈다")
  func launchWithoutHandler() async throws {
    let fake = CommandClientFake { _ in .success() }

    let process = try await fake.launch(Self.tool, ["-avd", "a"], environment: ["HOME": "/h"])

    #expect(fake.exitStatus(process) == nil)
    let waiting = Task { await fake.waitForExit(process) }
    fake.exit(process, status: 0)
    #expect(await waiting.value == 0)
    #expect(fake.exitStatus(process) == 0)
    #expect(fake.invocations == [CommandClientFake.Invocation(
      executable: Self.tool,
      arguments: ["-avd", "a"],
      environment: ["HOME": "/h"],
      isLaunch: true
    )])
  }

  @Test("launchHandler 가 받은 exit 로 끝나는 시점을 정하고, 던지면 그대로 던진다")
  func launchHandler() async throws {
    let fake = CommandClientFake(
      handler: { _ in .success() },
      launchHandler: { invocation, _, exit throws(CommandError) in
        guard invocation.arguments == ["ok"] else {
          throw .launchFailed
        }
        exit(9)
      }
    )

    let process = try await fake.launch(Self.tool, ["ok"], environment: [:])
    await #expect(throws: CommandError.launchFailed) {
      try await fake.launch(Self.tool, ["fail"], environment: [:])
    }

    #expect(fake.exitStatus(process) == 9)
    #expect(await fake.waitForExit(process) == 9)
    #expect(fake.invocations.map(\.isLaunch) == [true, true])
  }

  @Test("interrupt 를 기록하고, 도는 프로세스에만 interruptHandler 를 부른다")
  func interruptRecords() async throws {
    let fake = CommandClientFake { _ in .success() }
    let handled = Mutex<[LaunchedProcess]>([])
    let handling = CommandClientFake(
      handler: { _ in .success() },
      interruptHandler: { process in
        handled.withLock { $0.append(process) }
      }
    )
    let running = try await handling.launch(Self.tool, [], environment: [:])
    let finished = try await handling.launch(Self.tool, [], environment: [:])
    handling.exit(finished, status: 0)

    handling.interrupt(running)
    handling.interrupt(finished)
    fake.interrupt(running)

    #expect(handling.interrupts == [running, finished])
    #expect(handled.withLock { $0 } == [running])
    #expect(fake.interrupts == [running])
  }

  @Test("terminate 를 기록하고, 도는 프로세스에만 terminateHandler 를 부른다")
  func terminateRecords() async throws {
    let fake = CommandClientFake { _ in .success() }
    let handled = Mutex<[LaunchedProcess]>([])
    let handling = CommandClientFake(
      handler: { _ in .success() },
      terminateHandler: { process in
        handled.withLock { $0.append(process) }
      }
    )
    let running = try await handling.launch(Self.tool, [], environment: [:])
    let finished = try await handling.launch(Self.tool, [], environment: [:])
    handling.exit(finished, status: 0)

    handling.terminate(running)
    handling.terminate(finished)
    fake.terminate(running)

    #expect(handling.terminates == [running, finished])
    #expect(handling.interrupts.isEmpty)
    #expect(handled.withLock { $0 } == [running])
    #expect(fake.terminates == [running])
  }

  @Test("terminateHandler 가 exit 를 부르면 기다리는 쪽이 그 종료 상태를 받는다")
  func terminateHandlerExits() async throws {
    let exits = Mutex<[LaunchedProcess: @Sendable (Int32) -> Void]>([:])
    let fake = CommandClientFake(
      handler: { _ in .success() },
      launchHandler: { _, process, exit in
        exits.withLock { $0[process] = exit }
      },
      terminateHandler: { process in
        let exit = exits.withLock { $0[process] }
        exit?(128 + SIGTERM)
      }
    )
    let process = try await fake.launch(Self.tool, [], environment: [:])

    fake.terminate(process)

    #expect(await fake.waitForExit(process) == 128 + SIGTERM)
  }

  @Test("waitForExit 를 부른 Task 를 취소하면 nil, 프로세스는 그대로 돈다")
  func cancelledWait() async throws {
    let fake = CommandClientFake { _ in .success() }
    let process = try await fake.launch(Self.tool, [], environment: [:])
    let waiting = Task { await fake.waitForExit(process) }

    waiting.cancel()

    #expect(await waiting.value == nil)
    #expect(fake.exitStatus(process) == nil)
  }

  @Test("띄우지 않은 값은 -1, 두 번째 exit 는 무시한다")
  func unknownAndRepeatedExit() async throws {
    let fake = CommandClientFake { _ in .success() }
    let unknown = LaunchedProcess(id: UUID())
    let process = try await fake.launch(Self.tool, [], environment: [:])

    fake.exit(process, status: 1)
    fake.exit(process, status: 2)

    #expect(fake.exitStatus(unknown) == -1)
    #expect(await fake.waitForExit(unknown) == -1)
    #expect(fake.exitStatus(process) == 1)
  }
}
