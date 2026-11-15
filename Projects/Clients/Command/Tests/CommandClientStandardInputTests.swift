import CommandImpl
import CommandInterface
import CommandTesting
import Foundation
import Testing

/// `run(_:_:environment:standardInput:)`: 실제 프로세스(Impl)와 기록(Fake).
struct CommandClientStandardInputTests {
  private static let cat = URL(filePath: "/bin/cat")
  private static let mebibyte = Data((0 ..< 1_048_576).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })

  @Test("stdin 으로 넘긴 바이트를 /bin/cat 이 그대로 stdout 으로 돌려준다 (UTF-8·줄바꿈 그대로)", .timeLimit(.minutes(1)))
  func catRoundTrip() async throws {
    let input = Data("{\"aps\":{\"alert\":\"한글 \\u00e9\"}}\n  끝\n".utf8)

    let result = try await CommandClientImpl().run(Self.cat, [], environment: [:], standardInput: input)

    #expect(result.exitCode == 0)
    #expect(result.stdout == input)
    #expect(result.stderr.isEmpty)
  }

  @Test("1 MiB 입력과 1 MiB 출력이 동시에 오가도 막히지 않는다 (파이프 버퍼 64KB 보다 큼)", .timeLimit(.minutes(1)))
  func largeInputAndOutput() async throws {
    let result = try await CommandClientImpl().run(Self.cat, [], environment: [:], standardInput: Self.mebibyte)

    #expect(result.exitCode == 0)
    #expect(result.stdout == Self.mebibyte)
  }

  @Test("stdin 을 읽지 않고 끝나는 프로세스에 1 MiB 를 넘겨도 앱이 죽지 않고 결과를 돌려준다 (SIGPIPE 막음)", .timeLimit(.minutes(1)))
  func childExitsWithoutReading() async throws {
    let result = try await CommandClientImpl().run(
      URL(filePath: "/usr/bin/true"),
      [],
      environment: [:],
      standardInput: Self.mebibyte
    )

    #expect(result.exitCode == 0)
    #expect(result.stdout.isEmpty)
  }

  @Test("빈 입력은 곧바로 EOF 다", .timeLimit(.minutes(1)))
  func emptyInput() async throws {
    let result = try await CommandClientImpl().run(Self.cat, [], environment: [:], standardInput: Data())

    #expect(result.exitCode == 0)
    #expect(result.stdout.isEmpty)
  }

  @Test("stderr 와 0 이 아닌 종료 코드를 결과로 돌려준다 (stdin 을 읽은 뒤)", .timeLimit(.minutes(1)))
  func stderrAndExitCode() async throws {
    let result = try await CommandClientImpl().run(
      URL(filePath: "/bin/sh"),
      ["-c", "cat >&2; exit 28"],
      environment: [:],
      standardInput: Data("payload".utf8)
    )

    #expect(result.exitCode == 28)
    #expect(result.stderr == Data("payload".utf8))
    #expect(result.stdout.isEmpty)
  }

  @Test("없는 실행 파일은 launchFailed 를 던진다")
  func missingExecutableThrows() async {
    await #expect(throws: CommandError.launchFailed) {
      try await CommandClientImpl().run(
        URL(filePath: "/nonexistent/tool"),
        [],
        environment: [:],
        standardInput: Self.mebibyte
      )
    }
  }

  @Test("Fake: stdin 바이트를 기록하고 handler 결과를 돌려준다. 기존 run 은 standardInput 이 nil 이다")
  func fakeRecordsStandardInput() async throws {
    let tool = URL(filePath: "/usr/bin/tool")
    let fake = CommandClientFake { invocation in
      invocation.standardInput == nil ? .success(Data("plain".utf8)) : .failure(28, "too large")
    }

    let piped = try await fake.run(tool, ["push", "-"], environment: ["K": "1"], standardInput: Data("{}".utf8))
    let plain = try await fake.run(tool, ["list"], environment: [:])

    #expect(piped.exitCode == 28)
    #expect(piped.stderr == Data("too large".utf8))
    #expect(plain.stdout == Data("plain".utf8))
    #expect(
      fake.invocations == [
        CommandClientFake.Invocation(
          executable: tool,
          arguments: ["push", "-"],
          environment: ["K": "1"],
          standardInput: Data("{}".utf8)
        ),
        CommandClientFake.Invocation(executable: tool, arguments: ["list"], environment: [:]),
      ]
    )
    #expect(fake.invocations.map(\.standardInput) == [Data("{}".utf8), nil])
  }
}
