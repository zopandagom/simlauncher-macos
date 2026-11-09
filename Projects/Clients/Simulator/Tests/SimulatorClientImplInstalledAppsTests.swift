import CommandInterface
import CommandTesting
import Core
import Foundation
import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// installedApps 의 인자·환경·해석·분류. 목록을 다시 읽지 않는다.
struct SimulatorClientImplInstalledAppsTests {
  private static let udid = "B66201ED-154C-4F97-A6C7-C88F42E8D3A7"
  private static let developer = URL(filePath: "/X/Xcode.app/Contents/Developer", directoryHint: .isDirectory)

  @Test("UDID 형식이 아니면 provider·프로세스 없이 deviceNotFound", arguments: ["", "-h", "iPhone 17", "booted"])
  func invalidUDID(raw: String) async throws {
    let command = CommandClientFake { _ in .success() }
    let counter = ProviderCounter(returning: Self.developer)

    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.client(command, provider: counter).installedApps(on: VirtualDevice.ID(raw))
    }
    #expect(command.invocations.isEmpty)
    #expect(counter.calls == 0)
  }

  @Test("대문자 UDID 를 -- 없이 넘기고 DEVELOPER_DIR 를 전하며, 0 종료면 출력을 해석한다 (명령 한 번)")
  func argumentsAndDecoding() async throws {
    let stdout = try Fixture.data("listapps-sample", withExtension: "txt")
    let command = CommandClientFake { _ in .success(stdout) }
    let counter = ProviderCounter(returning: Self.developer)

    let apps = try await Self.client(command, provider: counter)
      .installedApps(on: VirtualDevice.ID(Self.udid.lowercased()))

    #expect(command.invocations.count == 1)
    let invocation = try #require(command.invocations.first)
    #expect(invocation.executable == SimctlCommand.xcrun)
    #expect(invocation.arguments == ["simctl", "listapps", Self.udid])
    #expect(invocation.environment["DEVELOPER_DIR"] == "/X/Xcode.app/Contents/Developer/")
    #expect(counter.calls == 1)
    #expect(try apps == (SimctlAppListDecoder.apps(from: stdout)))
    #expect(apps.count == 7)
  }

  @Test("0 종료여도 최상위가 사전이 아니면 unexpectedOutput")
  func unexpectedOutput() async throws {
    let command = CommandClientFake { _ in .success(Data("( a )".utf8)) }

    await #expect(throws: SimulatorError.unexpectedOutput) {
      try await Self.client(command).installedApps(on: VirtualDevice.ID(Self.udid))
    }
  }

  @Test(
    "listapps 실패는 분류한다",
    arguments: [
      (
        Int32(149),
        "An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=405):\n"
          + "Unable to lookup in current state: Shutdown\n",
        SimulatorError.deviceNotBooted
      ),
      (Int32(148), "Invalid device: 00000000-0000-0000-0000-000000000000\n", SimulatorError.deviceNotFound),
      (Int32(1), "xcrun: error: missing DEVELOPER_DIR path: /nonexistent\n", SimulatorError.developerToolsUnavailable),
    ]
  )
  func failure(exitCode: Int32, stderr: String, expected: SimulatorError) async throws {
    let command = CommandClientFake { _ in .failure(exitCode, stderr) }

    await #expect(throws: expected) {
      try await Self.client(command).installedApps(on: VirtualDevice.ID(Self.udid))
    }
    #expect(command.invocations.count == 1)
  }

  @Test("프로세스를 시작하지 못하면 developerToolsUnavailable")
  func launchFailure() async throws {
    let command = CommandClientFake { _ throws(CommandError) in throw .launchFailed }

    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(command).installedApps(on: VirtualDevice.ID(Self.udid))
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
