import CommandInterface
import CommandTesting
import Core
import Foundation
import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// openURL 의 인자·환경·분류. 목록을 다시 읽지 않는다.
struct SimulatorClientImplOpenURLTests {
  private static let udid = "B66201ED-154C-4F97-A6C7-C88F42E8D3A7"
  private static let developer = URL(filePath: "/X/Xcode.app/Contents/Developer", directoryHint: .isDirectory)
  private static let link = DeepLink("https://example.com/검색?q=한글")!

  @Test("UDID 형식이 아니면 provider·프로세스 없이 deviceNotFound", arguments: ["", "-h", "iPhone 17", "booted"])
  func invalidUDID(raw: String) async throws {
    let command = CommandClientFake { _ in .success() }
    let counter = ProviderCounter(returning: Self.developer)

    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.client(command, provider: counter).openURL(Self.link, on: VirtualDevice.ID(raw))
    }
    #expect(command.invocations.isEmpty)
    #expect(counter.calls == 0)
  }

  @Test("대문자 UDID 와 인코딩한 링크를 -- 없이 넘기고, 성공하면 목록을 읽지 않는다")
  func arguments() async throws {
    let command = CommandClientFake { _ in .success() }
    let counter = ProviderCounter(returning: Self.developer)

    try await Self.client(command, provider: counter).openURL(Self.link, on: VirtualDevice.ID(Self.udid.lowercased()))

    #expect(command.invocations.count == 1)
    let invocation = try #require(command.invocations.first)
    #expect(invocation.executable == SimctlCommand.xcrun)
    #expect(invocation.arguments == [
      "simctl", "openurl", Self.udid, "https://example.com/%EA%B2%80%EC%83%89?q=%ED%95%9C%EA%B8%80",
    ])
    #expect(invocation.environment["DEVELOPER_DIR"] == "/X/Xcode.app/Contents/Developer/")
    #expect(counter.calls == 1)
  }

  @Test(
    "openurl 실패는 domain 줄로 분류한다",
    arguments: [
      (
        Int32(115),
        "An error was encountered processing the command (domain=LSApplicationWorkspaceErrorDomain, code=115):\n"
          + "Simulator device failed to open https://example.com.\n",
        SimulatorError.urlNotHandled
      ),
      (
        Int32(149),
        "An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=405):\n"
          + "Unable to lookup in current state: Shutdown\n",
        SimulatorError.deviceNotBooted
      ),
    ]
  )
  func failure(exitCode: Int32, stderr: String, expected: SimulatorError) async throws {
    let command = CommandClientFake { _ in .failure(exitCode, stderr) }

    await #expect(throws: expected) {
      try await Self.client(command).openURL(Self.link, on: VirtualDevice.ID(Self.udid))
    }
    #expect(command.invocations.count == 1)
  }

  @Test("잘못된 UTF-8 이 섞인 stderr 도 domain 줄로 분류한다")
  func failureWithInvalidUTF8() async throws {
    let stderr = Data(
      "An error was encountered processing the command (domain=LSApplicationWorkspaceErrorDomain, code=115):\n".utf8
    ) + Data([0xFF, 0xFE, 0x0A])
    let command = CommandClientFake { _ in CommandResult(exitCode: 115, stdout: Data(), stderr: stderr) }

    await #expect(throws: SimulatorError.urlNotHandled) {
      try await Self.client(command).openURL(Self.link, on: VirtualDevice.ID(Self.udid))
    }
  }

  @Test("프로세스를 시작하지 못하면 developerToolsUnavailable")
  func launchFailure() async throws {
    let command = CommandClientFake { _ throws(CommandError) in throw .launchFailed }

    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(command).openURL(Self.link, on: VirtualDevice.ID(Self.udid))
    }
  }

  private static func client(_ command: CommandClientFake, provider: ProviderCounter? = nil) -> SimulatorClientImpl {
    SimulatorClientImpl(
      developerDirectory: provider.map { counter in { @Sendable in counter.provide() } },
      command: command,
      fileExists: { _ in false },
      baseEnvironment: [:]
    )
  }
}
