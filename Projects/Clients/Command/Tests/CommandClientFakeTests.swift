import CommandInterface
import CommandTesting
import Foundation
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
}
