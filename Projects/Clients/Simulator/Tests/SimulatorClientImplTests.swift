import Core
import Foundation
import SimulatorInterface
import Testing
@testable import SimulatorImpl

struct SimulatorClientImplTests {
  private static let udid = "00000000-0000-0000-0000-000000000001"
  private static let developer = URL(filePath: "/X/Xcode.app/Contents/Developer", directoryHint: .isDirectory)
  private static let booted = "Unable to boot device in current state: Booted"

  @Test("목록은 simctl list -j 한 번이고 출력을 해석한다")
  func fetchInventory() async throws {
    let fixture = try Fixture.data("simctl-list")
    let runner = StubCommandRunner { _ in .success(fixture) }
    let client = Self.client(runner: runner)

    let inventory = try await client.fetchInventory()

    #expect(inventory.devices.count == 9)
    #expect(runner.invocations.map(\.arguments) == [["simctl", "list", "-j"]])
    #expect(runner.invocations.first?.executable == SimctlCommand.xcrun)
  }

  @Test("목록 명령이 실패하면 stderr 로 분류한다")
  func fetchInventoryFailure() async {
    let runner = StubCommandRunner { _ in .failure(72, "xcrun: error: unable to find utility \"simctl\"") }
    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(runner: runner).fetchInventory()
    }
  }

  @Test("목록 출력이 JSON 이 아니면 unexpectedOutput")
  func fetchInventoryBrokenOutput() async {
    let runner = StubCommandRunner { _ in .success(Data("oops".utf8)) }
    await #expect(throws: SimulatorError.unexpectedOutput) {
      try await Self.client(runner: runner).fetchInventory()
    }
  }

  @Test("프로세스를 시작하지 못하면 developerToolsUnavailable")
  func launchFailure() async {
    let runner = StubCommandRunner { _ in throw StubCommandRunner.LaunchError() }
    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(runner: runner).fetchInventory()
    }
  }

  @Test("boot 이 성공하면 재조회하지 않는다")
  func bootSuccess() async throws {
    let runner = StubCommandRunner { _ in .success() }
    try await Self.client(runner: runner).boot(VirtualDevice.ID(Self.udid))
    #expect(runner.invocations.map(\.arguments) == [["simctl", "boot", Self.udid]])
  }

  @Test("boot 이 실패해도 재조회에서 켜져 있으면 성공이다")
  func bootFailureButBooted() async throws {
    let fixture = try Fixture.data("simctl-list")
    let runner = StubCommandRunner { invocation in
      invocation.arguments.contains("boot") ? .failure(149, Self.booted) : .success(fixture)
    }
    try await Self.client(runner: runner).boot(VirtualDevice.ID(Self.udid))
    #expect(runner.invocations.map(\.arguments) == [["simctl", "boot", Self.udid], ["simctl", "list", "-j"]])
  }

  @Test("boot 이 실패하고 재조회에서 꺼져 있으면 처음 실패를 분류한 에러다")
  func bootFailureStillShutdown() async throws {
    let fixture = try Fixture.data("simctl-list")
    let runner = StubCommandRunner { invocation in
      invocation.arguments.contains("boot") ? .failure(148, "Invalid device: x") : .success(fixture)
    }
    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.client(runner: runner).boot(VirtualDevice.ID("00000000-0000-0000-0000-000000000002"))
    }
  }

  @Test("boot 이 실패하고 재조회도 실패하면 처음 실패를 분류한 에러다")
  func bootFailureAndListFailure() async {
    let runner = StubCommandRunner { invocation in
      invocation.arguments.contains("boot") ? .failure(149, Self.booted) : .failure(1, "xcrun: error: gone")
    }
    await #expect(throws: SimulatorError.commandFailed) {
      try await Self.client(runner: runner).boot(VirtualDevice.ID(Self.udid))
    }
    #expect(runner.invocations.count == 2)
  }

  @Test("UDID 형식이 아니면 프로세스를 실행하지 않고 deviceNotFound", arguments: ["-h", "iPhone 17", ""])
  func invalidUDID(raw: String) async {
    let runner = StubCommandRunner { _ in .success() }
    let client = Self.client(runner: runner)
    await #expect(throws: SimulatorError.deviceNotFound) {
      try await client.boot(VirtualDevice.ID(raw))
    }
    await #expect(throws: SimulatorError.deviceNotFound) {
      try await client.shutdown(VirtualDevice.ID(raw))
    }
    #expect(runner.invocations.isEmpty)
  }

  @Test("소문자 UDID 는 대문자로 넘긴다")
  func lowercaseUDID() async throws {
    let runner = StubCommandRunner { _ in .success() }
    try await Self.client(runner: runner).shutdown(VirtualDevice.ID("0a1b2c3d-0000-4000-8000-00000000abcd"))
    #expect(runner.invocations.map(\.arguments) == [["simctl", "shutdown", "0A1B2C3D-0000-4000-8000-00000000ABCD"]])
  }

  @Test("shutdown 이 실패해도 재조회에서 꺼져 있으면 성공이다")
  func shutdownFailureButShutdown() async throws {
    let fixture = try Fixture.data("simctl-list")
    let runner = StubCommandRunner { invocation in
      invocation.arguments.contains("shutdown") ? .failure(149, "Unable to shutdown device in current state: Shutdown")
        : .success(fixture)
    }
    try await Self.client(runner: runner).shutdown(VirtualDevice.ID("00000000-0000-0000-0000-000000000002"))
  }

  @Test("shutdown 이 실패하고 재조회에서 켜져 있으면 실패다")
  func shutdownFailureStillBooted() async throws {
    let fixture = try Fixture.data("simctl-list")
    let runner = StubCommandRunner { invocation in
      invocation.arguments.contains("shutdown") ? .failure(1, "boom") : .success(fixture)
    }
    await #expect(throws: SimulatorError.commandFailed) {
      try await Self.client(runner: runner).shutdown(VirtualDevice.ID(Self.udid))
    }
  }

  @Test("provider 가 준 디렉터리를 DEVELOPER_DIR 로 쓰고, 한 호출에서 provider 는 한 번만 부른다")
  func providerDirectoryIsUsedOnce() async throws {
    let fixture = try Fixture.data("simctl-list")
    let counter = ProviderCounter(returning: Self.developer)
    let runner = StubCommandRunner { invocation in
      invocation.arguments.contains("boot") ? .failure(149, Self.booted) : .success(fixture)
    }
    let client = SimulatorClientImpl(
      developerDirectory: { counter.provide() },
      runner: runner,
      fileExists: { _ in false },
      baseEnvironment: ["DEVELOPER_DIR": "/old", "PATH": "/usr/bin"]
    )

    try await client.boot(VirtualDevice.ID(Self.udid))

    #expect(counter.calls == 1)
    #expect(runner.invocations.count == 2)
    #expect(runner.invocations.allSatisfy {
      $0.environment == ["DEVELOPER_DIR": "/X/Xcode.app/Contents/Developer/", "PATH": "/usr/bin"]
    })
  }

  @Test("provider 가 없으면 물려받은 DEVELOPER_DIR 를 지운다")
  func noProviderClearsDeveloperDir() async throws {
    let fixture = try Fixture.data("simctl-list-empty")
    let runner = StubCommandRunner { _ in .success(fixture) }
    let client = SimulatorClientImpl(
      developerDirectory: nil,
      runner: runner,
      fileExists: { _ in false },
      baseEnvironment: ["DEVELOPER_DIR": "/old", "PATH": "/usr/bin"]
    )
    _ = try await client.fetchInventory()
    #expect(runner.invocations.first?.environment == ["PATH": "/usr/bin"])
  }

  @Test("provider 가 디렉터리를 주면 xcode-select 없이 그 안의 앱을 연다")
  func openAppWithProvider() async throws {
    let runner = StubCommandRunner { _ in .success() }
    let deviceHub = "/X/Xcode.app/Contents/Applications/DeviceHub.app/"
    let client = SimulatorClientImpl(
      developerDirectory: { Self.developer },
      runner: runner,
      fileExists: { $0.path(percentEncoded: false) == deviceHub },
      baseEnvironment: [:]
    )

    try await client.openSimulatorApp()

    #expect(runner.invocations.map(\.executable) == [SimctlCommand.open])
    #expect(runner.invocations.first?.arguments == [deviceHub])
    #expect(runner.invocations.first?.environment["DEVELOPER_DIR"] == "/X/Xcode.app/Contents/Developer/")
  }

  @Test("첫 후보(Simulator.app)가 있으면 그것을 연다")
  func openAppPrefersSimulatorApp() async throws {
    let runner = StubCommandRunner { _ in .success() }
    let client = SimulatorClientImpl(
      developerDirectory: { Self.developer },
      runner: runner,
      fileExists: { _ in true },
      baseEnvironment: [:]
    )
    try await client.openSimulatorApp()
    #expect(runner.invocations.first?.arguments == ["/X/Xcode.app/Contents/Developer/Applications/Simulator.app/"])
  }

  @Test("provider 가 없거나 nil 을 주면 DEVELOPER_DIR 를 지운 환경에서 xcode-select -p 로 찾는다", arguments: [false, true])
  func openAppWithXcodeSelect(hasProvider: Bool) async throws {
    let runner = StubCommandRunner { invocation in
      invocation.executable == SimctlCommand.xcodeSelect ? .success(Data("/Y/Xcode.app/Contents/Developer\n".utf8))
        : .success()
    }
    let returnsNil: DeveloperDirectoryProvider = { nil }
    let provider = hasProvider ? returnsNil : nil
    let client = SimulatorClientImpl(
      developerDirectory: provider,
      runner: runner,
      fileExists: { $0.path(percentEncoded: false).hasSuffix("DeviceHub.app/") },
      baseEnvironment: ["DEVELOPER_DIR": "/old"]
    )

    try await client.openSimulatorApp()

    #expect(runner.invocations.map(\.executable) == [SimctlCommand.xcodeSelect, SimctlCommand.open])
    #expect(runner.invocations[0].arguments == ["-p"])
    #expect(runner.invocations[0].environment["DEVELOPER_DIR"] == nil)
    #expect(runner.invocations[1].arguments == ["/Y/Xcode.app/Contents/Applications/DeviceHub.app/"])
  }

  @Test(
    "xcode-select 가 실패하거나 출력이 경로가 아니면 developerToolsUnavailable",
    arguments: [CommandResult.failure(2, "xcode-select: error"), .success(Data()), .success(Data("relative\n".utf8))]
  )
  func openAppXcodeSelectFailure(result: CommandResult) async {
    let runner = StubCommandRunner { _ in result }
    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(runner: runner, fileExists: { _ in true }).openSimulatorApp()
    }
    #expect(runner.invocations.count == 1)
  }

  @Test("후보 앱이 없으면 simulatorAppNotFound")
  func openAppNotFound() async {
    let runner = StubCommandRunner { _ in .success() }
    let client = SimulatorClientImpl(
      developerDirectory: { Self.developer },
      runner: runner,
      fileExists: { _ in false },
      baseEnvironment: [:]
    )
    await #expect(throws: SimulatorError.simulatorAppNotFound) {
      try await client.openSimulatorApp()
    }
    #expect(runner.invocations.isEmpty)
  }

  @Test("open 이 실패하면 commandFailed")
  func openAppOpenFails() async {
    let runner = StubCommandRunner { _ in .failure(1, "LSOpenURLsWithRole() failed") }
    let client = SimulatorClientImpl(
      developerDirectory: { Self.developer },
      runner: runner,
      fileExists: { _ in true },
      baseEnvironment: [:]
    )
    await #expect(throws: SimulatorError.commandFailed) {
      try await client.openSimulatorApp()
    }
  }

  private static func client(
    runner: StubCommandRunner,
    fileExists: @escaping @Sendable (URL) -> Bool = { _ in false }
  ) -> SimulatorClientImpl {
    SimulatorClientImpl(developerDirectory: nil, runner: runner, fileExists: fileExists, baseEnvironment: [:])
  }
}
