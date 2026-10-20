import CommandInterface
import CommandTesting
import Core
import Foundation
import SimulatorInterface
import Testing
@testable import SimulatorImpl

struct SimulatorClientImplRuntimeTests {
  private static let developer = URL(filePath: "/X/Xcode.app/Contents/Developer", directoryHint: .isDirectory)

  @Test("런타임 이미지 목록은 provider 의 DEVELOPER_DIR 로 xcrun simctl runtime list -j 한 번이고 출력을 해석한다")
  func fetchRuntimeImages() async throws {
    let fixture = try Fixture.data("simctl-runtime-list")
    let command = CommandClientFake { _ in .success(fixture) }
    let counter = ProviderCounter(returning: Self.developer)
    let client = SimulatorClientImpl(
      developerDirectory: { counter.provide() },
      command: command,
      fileExists: { _ in false },
      baseEnvironment: ["PATH": "/usr/bin", "DEVELOPER_DIR": "/old"]
    )

    let images = try await client.fetchRuntimeImages()

    #expect(images.map(\.id.rawValue) == [
      "00000000-0000-0000-0002-000000000001",
      "00000000-0000-0000-0002-000000000002",
      "00000000-0000-0000-0002-000000000003",
    ])
    #expect(counter.calls == 1)
    #expect(command.invocations.map(\.executable) == [SimctlCommand.xcrun])
    #expect(command.invocations.map(\.arguments) == [["simctl", "runtime", "list", "-j"]])
    #expect(command.invocations.first?.environment == [
      "PATH": "/usr/bin",
      "DEVELOPER_DIR": "/X/Xcode.app/Contents/Developer/",
    ])
  }

  @Test("provider 가 nil 을 돌려주면 명령 없이 developerToolsUnavailable 이고, provider 는 한 번이다")
  func providerReturnsNil() async {
    let command = CommandClientFake { _ in .success() }
    let counter = ProviderCounter(returning: nil)
    let client = SimulatorClientImpl(
      developerDirectory: { counter.provide() },
      command: command,
      fileExists: { _ in true },
      baseEnvironment: [:]
    )

    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await client.fetchRuntimeImages()
    }
    #expect(command.invocations.isEmpty)
    #expect(counter.calls == 1)
  }

  @Test("프로세스를 시작하지 못하면 developerToolsUnavailable")
  func launchFailure() async {
    let command = CommandClientFake { _ throws(CommandError) in throw .launchFailed }
    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(command: command).fetchRuntimeImages()
    }
  }

  @Test(
    "0 이 아닌 종료는 기존 분류를 따른다",
    arguments: [
      (
        CommandResult.failure(72, "xcrun: error: unable to find utility \"simctl\""),
        SimulatorError.developerToolsUnavailable
      ),
      (.failure(117, "simctl: unrecognized option"), .commandFailed),
    ] as [(CommandResult, SimulatorError)]
  )
  func nonZeroExit(result: CommandResult, expected: SimulatorError) async {
    let command = CommandClientFake { _ in result }
    await #expect(throws: expected) {
      try await Self.client(command: command).fetchRuntimeImages()
    }
  }

  @Test("출력이 사전 JSON 이 아니면 unexpectedOutput")
  func brokenOutput() async {
    let command = CommandClientFake { _ in .success(Data("[]".utf8)) }
    await #expect(throws: SimulatorError.unexpectedOutput) {
      try await Self.client(command: command).fetchRuntimeImages()
    }
  }

  private static func client(command: CommandClientFake) -> SimulatorClientImpl {
    SimulatorClientImpl(developerDirectory: nil, command: command, fileExists: { _ in false }, baseEnvironment: [:])
  }
}
