import CommandInterface
import CommandTesting
import Foundation
import Synchronization
import Testing

struct CommandClientFakeStreamTests {
  private static let tool = URL(filePath: "/usr/bin/tool")

  @Test("streamCancellable 은 isStream·isCancellable·timeout nil 로 기록하고, 처리기가 없으면 handler 결과를 조각으로 넘기고 stderr 만 돌려준다")
  func defaultPath() async throws {
    let fake = CommandClientFake { _ throws(CommandError) in
      CommandResult(exitCode: 2, stdout: Data("out".utf8), stderr: Data("err".utf8))
    }
    let received = Mutex<[CommandOutput]>([])

    let result = try await fake.streamCancellable(Self.tool, ["a"], environment: ["K": "V"]) { output in
      received.withLock { $0.append(output) }
    }

    #expect(result.exitCode == 2)
    #expect(result.stderr == Data("err".utf8))
    #expect(received.withLock { $0 } == [.stdout(Data("out".utf8)), .stderr(Data("err".utf8))])
    #expect(fake.invocations == [
      CommandClientFake.Invocation(
        executable: Self.tool,
        arguments: ["a"],
        environment: ["K": "V"],
        isCancellable: true,
        timeout: nil,
        isStream: true
      ),
    ])
  }

  @Test("cancellableHandler 가 있으면 그것을 쓰고, runCancellable 요청은 isStream false")
  func usesCancellableHandler() async throws {
    let fake = CommandClientFake(
      handler: { _ throws(CommandError) in .success(Data()) },
      cancellableHandler: { invocation, emit throws(CommandError) in
        await emit(.stdout(Data(invocation.isStream ? "stream".utf8 : "plain".utf8)))
        return CommandResult(exitCode: 0, stdout: Data("kept".utf8), stderr: Data("e".utf8))
      }
    )
    let received = Mutex<[CommandOutput]>([])

    let streamed = try await fake.streamCancellable(Self.tool, [], environment: [:]) { output in
      received.withLock { $0.append(output) }
    }
    _ = try await fake.runCancellable(Self.tool, [], environment: [:], timeout: nil) { output in
      received.withLock { $0.append(output) }
    }

    #expect(streamed.stderr == Data("e".utf8))
    #expect(received.withLock { $0 } == [.stdout(Data("stream".utf8)), .stdout(Data("plain".utf8))])
    #expect(fake.invocations.map(\.isStream) == [true, false])
  }

  @Test("이미 취소된 Task 면 기록하고 cancelled")
  func cancelledBeforeStart() async {
    let fake = CommandClientFake { _ throws(CommandError) in .success(Data()) }
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await fake.streamCancellable(Self.tool, [], environment: [:]) { _ in }
    }

    await #expect(throws: CommandError.cancelled) { try await task.value }
    #expect(fake.invocations.map(\.isStream) == [true])
  }
}
