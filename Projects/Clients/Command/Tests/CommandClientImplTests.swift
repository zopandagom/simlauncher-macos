import CommandImpl
import CommandInterface
import Foundation
import Testing

struct CommandClientImplTests {
  @Test("파이프 버퍼(64KB)보다 큰 stdout 도 멈추지 않고 끝까지 읽는다")
  func readsLargeOutput() async throws {
    let result = try await CommandClientImpl().run(
      URL(filePath: "/usr/bin/head"),
      ["-c", "200000", "/dev/zero"],
      environment: [:]
    )
    #expect(result.exitCode == 0)
    #expect(result.stdout.count == 200_000)
  }

  @Test("stderr 와 0 이 아닌 종료 코드를 결과로 돌려준다")
  func returnsStderrAndExitCode() async throws {
    let result = try await CommandClientImpl().run(
      URL(filePath: "/bin/sh"),
      ["-c", "echo err >&2; exit 3"],
      environment: [:]
    )
    #expect(result.exitCode == 3)
    #expect(String(bytes: result.stderr, encoding: .utf8) == "err\n")
    #expect(result.stdout.isEmpty)
  }

  @Test("없는 실행 파일은 launchFailed 를 던진다")
  func missingExecutableThrows() async {
    await #expect(throws: CommandError.launchFailed) {
      try await CommandClientImpl().run(URL(filePath: "/nonexistent/tool"), [], environment: [:])
    }
  }
}
