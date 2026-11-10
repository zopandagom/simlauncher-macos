import CommandInterface
import CommandTesting
import Foundation
import Synchronization
import Testing

struct CommandClientFakeTests {
  private static let tool = URL(filePath: "/usr/bin/tool")

  @Test("요청(실행 파일·인자·환경)을 순서대로 기록하고 handler 결과를 돌려준다")
  func recordsInvocations() async throws {
    let fake = CommandClientFake { invocation in
      invocation.arguments == ["a"] ? .success(Data("out".utf8)) : .failure(2, "err")
    }

    let first = try await fake.run(Self.tool, ["a"], environment: ["K": "1"])
    let second = try await fake.run(Self.tool, ["b", "c"], environment: [:])

    #expect(first.exitCode == 0)
    #expect(first.stdout == Data("out".utf8))
    #expect(second.exitCode == 2)
    #expect(second.stderr == Data("err".utf8))
    #expect(
      fake.invocations == [
        CommandClientFake.Invocation(executable: Self.tool, arguments: ["a"], environment: ["K": "1"]),
        CommandClientFake.Invocation(executable: Self.tool, arguments: ["b", "c"], environment: [:]),
      ]
    )
  }

  @Test("handler 가 던진 launchFailed 를 그대로 던지고 요청도 기록한다")
  func rethrowsLaunchFailed() async {
    let fake = CommandClientFake { _ throws(CommandError) in throw .launchFailed }

    await #expect(throws: CommandError.launchFailed) {
      try await fake.run(Self.tool, ["x"], environment: [:])
    }
    #expect(fake.invocations == [CommandClientFake.Invocation(
      executable: Self.tool,
      arguments: ["x"],
      environment: [:]
    )])
  }

  @Test("runCancellable 은 처리기가 없으면 handler 결과의 stdout·stderr 를 한 조각씩 넘기고, 시간 제한과 함께 기록한다")
  func cancellableWithoutHandler() async throws {
    let fake = CommandClientFake { _ in
      CommandResult(exitCode: 1, stdout: Data("out".utf8), stderr: Data("err".utf8))
    }
    let received = Mutex<[CommandOutput]>([])

    let result = try await fake.runCancellable(
      Self.tool,
      ["a"],
      environment: ["K": "1"],
      timeout: .seconds(30)
    ) { output in
      received.withLock { $0.append(output) }
    }

    #expect(result.exitCode == 1)
    let expected: [CommandOutput] = [.stdout(Data("out".utf8)), .stderr(Data("err".utf8))]
    #expect(received.withLock { $0 } == expected)
    #expect(fake.invocations == [CommandClientFake.Invocation(
      executable: Self.tool,
      arguments: ["a"],
      environment: ["K": "1"],
      isCancellable: true,
      timeout: .seconds(30)
    )])
  }

  @Test("runCancellable 은 빈 stdout·stderr 를 넘기지 않는다")
  func cancellableSkipsEmptyOutput() async throws {
    let fake = CommandClientFake { _ in .success() }
    let received = Mutex<[CommandOutput]>([])

    _ = try await fake.runCancellable(Self.tool, [], environment: [:], timeout: nil) { output in
      received.withLock { $0.append(output) }
    }

    #expect(received.withLock { $0 }.isEmpty)
    #expect(fake.invocations.first?.timeout == nil)
    #expect(fake.invocations.first?.isCancellable == true)
  }

  @Test("cancellableHandler 가 있으면 그것이 emit 한 조각과 결과를 쓴다")
  func cancellableHandler() async throws {
    let fake = CommandClientFake(
      handler: { _ throws(CommandError) in
        Issue.record("handler 를 부르지 않아야 한다")
        throw .launchFailed
      },
      cancellableHandler: { invocation, emit throws(CommandError) in
        await emit(.stdout(Data("1".utf8)))
        await emit(.stdout(Data("2".utf8)))
        guard invocation.arguments == ["go"] else {
          throw .timedOut
        }
        return .success(Data("12".utf8))
      }
    )
    let received = Mutex<[CommandOutput]>([])

    let result = try await fake.runCancellable(Self.tool, ["go"], environment: [:], timeout: nil) { output in
      received.withLock { $0.append(output) }
    }
    await #expect(throws: CommandError.timedOut) {
      try await fake.runCancellable(Self.tool, ["stop"], environment: [:], timeout: nil) { _ in }
    }

    #expect(result.stdout == Data("12".utf8))
    let expected: [CommandOutput] = [.stdout(Data("1".utf8)), .stdout(Data("2".utf8))]
    #expect(received.withLock { $0 } == expected)
    #expect(fake.invocations.map(\.arguments) == [["go"], ["stop"]])
  }

  @Test("처리기가 없을 때 첫 조각을 넘기는 중 취소되면 남은 조각은 넘기지 않고 결과는 전부 돌려준다")
  func cancelledWhileEmitting() async throws {
    let fake = CommandClientFake { _ in
      CommandResult(exitCode: 0, stdout: Data("out".utf8), stderr: Data("err".utf8))
    }
    let received = Mutex<[CommandOutput]>([])

    let task = Task {
      try await fake.runCancellable(Self.tool, [], environment: [:], timeout: nil) { output in
        received.withLock { $0.append(output) }
        withUnsafeCurrentTask { $0?.cancel() }
      }
    }
    let result = try await task.value

    #expect(received.withLock { $0 } == [CommandOutput.stdout(Data("out".utf8))])
    #expect(result.stdout == Data("out".utf8))
    #expect(result.stderr == Data("err".utf8))
  }

  @Test("이미 취소된 Task 의 runCancellable 은 기록하고 처리기 없이 cancelled")
  func cancellableAlreadyCancelled() async throws {
    let fake = CommandClientFake(
      handler: { _ throws(CommandError) in
        Issue.record("handler 를 부르지 않아야 한다")
        throw .launchFailed
      },
      cancellableHandler: { _, _ throws(CommandError) in
        Issue.record("cancellableHandler 를 부르지 않아야 한다")
        throw .launchFailed
      }
    )

    let task = Task {
      while !Task.isCancelled {
        await Task.yield()
      }
      return try await fake.runCancellable(Self.tool, ["x"], environment: [:], timeout: nil) { _ in }
    }
    task.cancel()

    await #expect(throws: CommandError.cancelled) { try await task.value }
    #expect(fake.invocations.map(\.isCancellable) == [true])
  }

  @Test("run 요청은 isCancellable false·timeout nil 로 기록된다 (3-인자 Invocation 과 같다)")
  func runInvocationDefaults() async throws {
    let fake = CommandClientFake { _ in .success() }
    _ = try await fake.run(Self.tool, ["a"], environment: [:])

    let invocation = try #require(fake.invocations.first)
    #expect(!invocation.isCancellable)
    #expect(invocation.timeout == nil)
    #expect(invocation == CommandClientFake.Invocation(executable: Self.tool, arguments: ["a"], environment: [:]))
  }
}
