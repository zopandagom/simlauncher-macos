import CommandInterface
import CommandTesting
import Core
import Foundation
import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// screenshot 의 인자·환경·사전 확인·분류. 목록은 `simctl-list` 픽스처다 (…0001 켜짐, …0002 꺼짐).
struct SimulatorClientImplScreenshotTests {
  private static let list = ["simctl", "list", "-j"]
  private static let booted = VirtualDevice.ID("00000000-0000-0000-0000-000000000001")
  private static let shutdown = VirtualDevice.ID("00000000-0000-0000-0000-000000000002")
  private static let missing = VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF")
  private static let developer = URL(filePath: "/X/Xcode.app/Contents/Developer", directoryHint: .isDirectory)
  private static let file = URL(filePath: "/P/SimLauncher/iPhone 17 (iOS 27.0) 2026-10-25 14.21.33.png")

  @Test("UDID 형식이 아니면 provider·프로세스 없이 deviceNotFound", arguments: ["", "-h", "iPhone 17", "booted"])
  func invalidUDID(raw: String) async throws {
    let command = try Self.command(returning: .success())
    let counter = ProviderCounter(returning: Self.developer)

    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.client(command, provider: counter).screenshot(on: VirtualDevice.ID(raw), to: Self.file)
    }
    #expect(command.invocations.isEmpty)
    #expect(counter.calls == 0)
  }

  @Test("파일 URL 이 아니면 provider·프로세스 없이 commandFailed")
  func notFileURL() async throws {
    let command = try Self.command(returning: .success())
    let counter = ProviderCounter(returning: Self.developer)

    await #expect(throws: SimulatorError.commandFailed) {
      try await Self.client(command, provider: counter)
        .screenshot(on: Self.booted, to: #require(URL(string: "https://example.com/a.png")))
    }
    #expect(command.invocations.isEmpty)
    #expect(counter.calls == 0)
  }

  @Test("provider 가 nil 이면 프로세스 없이 developerToolsUnavailable")
  func noXcode() async throws {
    let command = try Self.command(returning: .success())
    let counter = ProviderCounter(returning: nil)

    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(command, provider: counter).screenshot(on: Self.booted, to: Self.file)
    }
    #expect(command.invocations.isEmpty)
    #expect(counter.calls == 1)
  }

  @Test("목록에 없는 기기는 목록만 읽고 deviceNotFound")
  func missingDevice() async throws {
    let command = try Self.command(returning: .success())

    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.client(command).screenshot(on: Self.missing, to: Self.file)
    }
    #expect(command.invocations.map(\.arguments) == [Self.list])
  }

  @Test("켜져 있지 않은 기기는 목록만 읽고 deviceNotBooted")
  func notBooted() async throws {
    let command = try Self.command(returning: .success())

    await #expect(throws: SimulatorError.deviceNotBooted) {
      try await Self.client(command).screenshot(on: Self.shutdown, to: Self.file)
    }
    #expect(command.invocations.map(\.arguments) == [Self.list])
  }

  @Test("켜진 기기는 목록 뒤에 대문자 UDID 와 표준화한 경로로 촬영하고, 두 명령이 같은 DEVELOPER_DIR 를 쓴다")
  func arguments() async throws {
    let command = try Self.command(returning: .success())
    let counter = ProviderCounter(returning: Self.developer)
    let messy = URL(filePath: "/P/SimLauncher/../SimLauncher/a b.png")

    try await Self.client(command, provider: counter)
      .screenshot(on: VirtualDevice.ID(Self.booted.rawValue.lowercased()), to: messy)

    #expect(command.invocations.map(\.arguments) == [
      Self.list,
      [
        "simctl", "io", Self.booted.rawValue, "screenshot", "--type=png", "--mask=ignored",
        "/P/SimLauncher/a b.png",
      ],
    ])
    #expect(command.invocations.map(\.executable) == [SimctlCommand.xcrun, SimctlCommand.xcrun])
    #expect(command.invocations.map { $0.environment["DEVELOPER_DIR"] } == [
      "/X/Xcode.app/Contents/Developer/", "/X/Xcode.app/Contents/Developer/",
    ])
    #expect(counter.calls == 1)
  }

  @Test("촬영 실패는 줄 머리 domain 으로 분류하고 재조회하지 않는다")
  func failure() async throws {
    let stderr = "An error was encountered processing the command (domain=NSPOSIXErrorDomain, code=60):\n"
      + "Timeout waiting for screen surfaces\n"
    let command = try Self.command(returning: .failure(60, stderr))

    await #expect(throws: SimulatorError.deviceNotBooted) {
      try await Self.client(command).screenshot(on: Self.booted, to: Self.file)
    }
    #expect(command.invocations.count == 2)
  }

  @Test("프로세스를 시작하지 못하면 developerToolsUnavailable")
  func launchFailure() async throws {
    let fixture = try Fixture.data("simctl-list")
    let command = CommandClientFake { invocation throws(CommandError) in
      if invocation.arguments == Self.list {
        return .success(fixture)
      }
      throw .launchFailed
    }

    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(command).screenshot(on: Self.booted, to: Self.file)
    }
  }

  private static func command(returning result: CommandResult) throws -> CommandClientFake {
    let fixture = try Fixture.data("simctl-list")
    return CommandClientFake { invocation in
      invocation.arguments == Self.list ? .success(fixture) : result
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
