import CommandInterface
import CommandTesting
import Core
import Foundation
import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// runningApplications·uninstall 의 인자·환경·해석·분류. 목록을 다시 읽지 않는다.
struct SimulatorClientImplLayoutTests {
  struct Failure: Sendable {
    let exitCode: Int32
    let stderr: String
    let expected: SimulatorError
  }

  enum Operation: String, CaseIterable, Sendable {
    case runningApplications, uninstall
  }

  private static let udid = "B66201ED-154C-4F97-A6C7-C88F42E8D3A7"
  private static let developer = URL(filePath: "/X/Xcode.app/Contents/Developer", directoryHint: .isDirectory)

  @Test(
    "UDID 형식이 아니면 provider·프로세스 없이 deviceNotFound",
    arguments: Operation.allCases,
    ["", "-h", "iPhone 17", "booted"]
  )
  func invalidUDID(operation: Operation, raw: String) async throws {
    let command = CommandClientFake { _ in .success() }
    let counter = ProviderCounter(returning: Self.developer)

    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.perform(operation, on: Self.client(command, provider: counter), id: VirtualDevice.ID(raw))
    }
    #expect(command.invocations.isEmpty)
    #expect(counter.calls == 0)
  }

  @Test("실행 중 앱 목록: 대문자 UDID 로 spawn launchctl list 를 한 번 실행하고 DEVELOPER_DIR 를 전하며, 출력을 해석한다")
  func runningApplicationsArgumentsAndParsing() async throws {
    let stdout = Data("""
    PID\tStatus\tLabel
    78490\t0\tUIKitApplication:com.apple.mobilecal[7e9f][rb-legacy]
    -\t0\tcom.apple.progressd
    11\t0\tUIKitApplication:\(IOSLayoutRunner.appBundleID)[1][rb-legacy]
    """.utf8)
    let command = CommandClientFake { _ in .success(stdout) }
    let counter = ProviderCounter(returning: Self.developer)

    let apps = try await Self.client(command, provider: counter)
      .runningApplications(on: VirtualDevice.ID(Self.udid.lowercased()))

    #expect(command.invocations.count == 1)
    let invocation = try #require(command.invocations.first)
    #expect(invocation.executable == SimctlCommand.xcrun)
    #expect(invocation.arguments == ["simctl", "spawn", Self.udid, "launchctl", "list"])
    #expect(invocation.environment["DEVELOPER_DIR"] == "/X/Xcode.app/Contents/Developer/")
    #expect(counter.calls == 1)
    #expect(apps.map(\.rawValue) == ["com.apple.mobilecal"])
  }

  @Test("실행 중 앱 목록: 0 종료여도 UTF-8 이 아니면 unexpectedOutput")
  func runningApplicationsUnexpectedOutput() async throws {
    let command = CommandClientFake { _ in .success(Data([0xFF, 0xFE])) }

    await #expect(throws: SimulatorError.unexpectedOutput) {
      try await Self.client(command).runningApplications(on: VirtualDevice.ID(Self.udid))
    }
  }

  @Test("앱 지우기: 대문자 UDID·번들 ID 를 -- 없이 한 번 실행하고 DEVELOPER_DIR 를 전한다")
  func uninstallArguments() async throws {
    let command = CommandClientFake { _ in .success() }
    let counter = ProviderCounter(returning: Self.developer)
    let bundleID = try #require(AppBundleID(IOSLayoutRunner.appBundleID))

    try await Self.client(command, provider: counter).uninstall(bundleID, on: VirtualDevice.ID(Self.udid.lowercased()))

    #expect(command.invocations.count == 1)
    let invocation = try #require(command.invocations.first)
    #expect(invocation.executable == SimctlCommand.xcrun)
    #expect(invocation.arguments == ["simctl", "uninstall", Self.udid, IOSLayoutRunner.appBundleID])
    #expect(invocation.environment["DEVELOPER_DIR"] == "/X/Xcode.app/Contents/Developer/")
    #expect(counter.calls == 1)
  }

  @Test(
    "실패는 listapps 와 같이 분류한다 (꺼진 기기 405, 없는 기기, xcrun 오류, 모르는 실패)",
    arguments: Operation.allCases,
    [
      Failure(
        exitCode: 149,
        stderr: "An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=405):\n"
          + "Unable to lookup in current state: Shutdown\n",
        expected: .deviceNotBooted
      ),
      Failure(
        exitCode: 148,
        stderr: "Invalid device: 00000000-0000-0000-0000-000000000000\n",
        expected: .deviceNotFound
      ),
      Failure(
        exitCode: 1,
        stderr: "xcrun: error: missing DEVELOPER_DIR path: /nonexistent\n",
        expected: .developerToolsUnavailable
      ),
      Failure(exitCode: 1, stderr: "Something went wrong\n", expected: .commandFailed),
    ]
  )
  func failure(operation: Operation, failure: Failure) async throws {
    let (exitCode, stderr, expected) = (failure.exitCode, failure.stderr, failure.expected)
    let command = CommandClientFake { _ in .failure(exitCode, stderr) }

    await #expect(throws: expected) {
      try await Self.perform(operation, on: Self.client(command), id: VirtualDevice.ID(Self.udid))
    }
    #expect(command.invocations.count == 1)
  }

  @Test("프로세스를 시작하지 못하면 developerToolsUnavailable", arguments: Operation.allCases)
  func launchFailure(operation: Operation) async throws {
    let command = CommandClientFake { _ throws(CommandError) in throw .launchFailed }

    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.perform(operation, on: Self.client(command), id: VirtualDevice.ID(Self.udid))
    }
  }

  private static func perform(
    _ operation: Operation,
    on client: SimulatorClientImpl,
    id: VirtualDevice.ID
  ) async throws(SimulatorError) {
    switch operation {
    case .runningApplications:
      _ = try await client.runningApplications(on: id)
    case .uninstall:
      try await client.uninstall(AppBundleID("com.example.app")!, on: id)
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
