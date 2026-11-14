import CommandInterface
import CommandTesting
import Core
import Foundation
import SimulatorInterface
import Synchronization
import Testing
@testable import SimulatorImpl

/// 테스트 조건(화면 설정 읽기·쓰기, 위치)의 실행 순서·판정·분류. 목록은 `simctl-list` 픽스처다 (…0001 켜짐, …0002 꺼짐).
struct SimulatorClientImplConditionsTests {
  private static let list = ["simctl", "list", "-j"]
  private static let booted = VirtualDevice.ID("00000000-0000-0000-0000-000000000001")
  private static let shutdown = VirtualDevice.ID("00000000-0000-0000-0000-000000000002")
  private static let missing = VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF")
  private static let udid = booted.rawValue
  private static let developer = URL(filePath: "/X/Xcode.app/Contents/Developer", directoryHint: .isDirectory)
  private static let notBootedStderr = "An error was encountered processing the command "
    + "(domain=com.apple.CoreSimulator.SimError, code=405):\nUnable to lookup in current state: Shutdown\n"

  /// 기기 안 `ui` 값 흉내: 쓰기는 `accepts` 가 true 일 때만 값을 바꾸고(exit 0 은 그대로), 읽기는 지금 값을 돌려준다.
  final class FakeUI: Sendable {
    private let values: Mutex<[String: String]>
    private let accepts: @Sendable (String, String) -> Bool

    init(
      _ values: [String: String] = ["appearance": "light", "content_size": "large", "increase_contrast": "disabled"],
      accepts: @escaping @Sendable (String, String) -> Bool = { _, _ in true }
    ) {
      self.values = Mutex(values)
      self.accepts = accepts
    }

    func respond(_ arguments: [String]) -> CommandResult? {
      guard arguments.count >= 4, arguments[0 ... 1] == ["simctl", "ui"] else { return nil }
      let option = arguments[3]
      if arguments.count == 5 {
        if self.accepts(option, arguments[4]) {
          self.values.withLock { $0[option] = arguments[4] }
          return .success()
        }
        return CommandResult(exitCode: 0, stdout: Data(), stderr: Data("Invalid argument\n".utf8))
      }
      return .success(Data((self.values.withLock { $0[option] } ?? "unknown").utf8 + [0x0A]))
    }
  }

  // MARK: - 화면 설정 읽기

  @Test("읽기: provider 한 번, 같은 DEVELOPER_DIR 로 appearance → content_size → increase_contrast, 목록은 읽지 않는다")
  func readsThree() async throws {
    let fakeUI = FakeUI(["appearance": "dark", "content_size": "extra-Small", "increase_contrast": "enabled"])
    let command = try Self.command(ui: fakeUI)
    let counter = ProviderCounter(returning: Self.developer)

    let settings = try await Self.client(command, provider: counter)
      .displaySettings(on: VirtualDevice.ID(Self.udid.lowercased()))

    #expect(settings == IOSDisplaySettings(
      appearance: .value(.dark),
      contentSize: .value(.extraSmall),
      increaseContrast: .value(true)
    ))
    #expect(command.invocations.map(\.arguments) == [
      ["simctl", "ui", Self.udid, "appearance"],
      ["simctl", "ui", Self.udid, "content_size"],
      ["simctl", "ui", Self.udid, "increase_contrast"],
    ])
    #expect(command.invocations.allSatisfy { $0.executable == SimctlCommand.xcrun })
    #expect(command.invocations.allSatisfy { $0.environment["DEVELOPER_DIR"] == "/X/Xcode.app/Contents/Developer/" })
    #expect(counter.calls == 1)
  }

  @Test("읽기: 셋 다 unknown 이면 목록을 읽어 꺼졌으면 deviceNotBooted, 없으면 deviceNotFound")
  func allUnknownChecksList() async throws {
    let fakeUI = FakeUI(["appearance": "unknown", "content_size": "unknown", "increase_contrast": "unknown"])

    let shutdownCommand = try Self.command(ui: fakeUI)
    await #expect(throws: SimulatorError.deviceNotBooted) {
      try await Self.client(shutdownCommand).displaySettings(on: Self.shutdown)
    }
    #expect(shutdownCommand.invocations.last?.arguments == Self.list)

    let missingCommand = try Self.command(ui: fakeUI)
    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.client(missingCommand).displaySettings(on: Self.missing)
    }
  }

  @Test("읽기: 셋 다 unknown 이어도 켜진 기기면 unknown 그대로")
  func allUnknownBooted() async throws {
    let fakeUI = FakeUI(["appearance": "unknown", "content_size": "unknown", "increase_contrast": "unknown"])
    let command = try Self.command(ui: fakeUI)

    let settings = try await Self.client(command).displaySettings(on: Self.booted)

    #expect(settings == IOSDisplaySettings(appearance: .unknown, contentSize: .unknown, increaseContrast: .unknown))
    #expect(command.invocations.map(\.arguments).filter { $0 == Self.list }.count == 1)
  }

  @Test("읽기: 하나라도 unknown 이 아니면 목록을 읽지 않는다 (unsupported 포함)")
  func partiallyUnsupported() async throws {
    let fakeUI = FakeUI(["appearance": "light", "content_size": "unsupported", "increase_contrast": "unknown"])
    let command = try Self.command(ui: fakeUI)

    let settings = try await Self.client(command).displaySettings(on: Self.booted)

    #expect(settings.contentSize == .unsupported)
    #expect(settings.increaseContrast == .unknown)
    #expect(!command.invocations.map(\.arguments).contains(Self.list))
  }

  @Test("읽기 실패: 405 → deviceNotBooted (첫 읽기에서 멈춘다), Invalid device → deviceNotFound")
  func readFailure() async throws {
    let notBooted = CommandClientFake { _ in .failure(149, Self.notBootedStderr) }
    await #expect(throws: SimulatorError.deviceNotBooted) {
      try await Self.client(notBooted).displaySettings(on: Self.booted)
    }
    #expect(notBooted.invocations.count == 1)

    let invalid = CommandClientFake { _ in .failure(148, "Invalid device: \(Self.udid)\n") }
    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.client(invalid).displaySettings(on: Self.booted)
    }
  }

  // MARK: - 화면 설정 쓰기

  @Test("쓰기: 쓴 뒤 세 값을 다시 읽어 요청과 같으면 applied (provider 한 번)")
  func writeApplied() async throws {
    let fakeUI = FakeUI()
    let command = try Self.command(ui: fakeUI)
    let counter = ProviderCounter(returning: Self.developer)

    let outcome = try await Self.client(command, provider: counter)
      .setDisplaySetting(.contentSize(.accessibilityExtraExtraExtraLarge), on: Self.booted)

    #expect(outcome == .applied)
    #expect(command.invocations.map(\.arguments) == [
      ["simctl", "ui", Self.udid, "content_size", "accessibility-extra-extra-extra-large"],
      ["simctl", "ui", Self.udid, "appearance"],
      ["simctl", "ui", Self.udid, "content_size"],
      ["simctl", "ui", Self.udid, "increase_contrast"],
    ])
    #expect(counter.calls == 1)
  }

  @Test("쓰기: exit 0 + Invalid argument 이고 다시 읽은 값이 다르면 notApplied(읽은 값)")
  func writeNotApplied() async throws {
    let fakeUI = FakeUI(accepts: { option, _ in option != "increase_contrast" })
    let command = try Self.command(ui: fakeUI)

    let outcome = try await Self.client(command).setDisplaySetting(.increaseContrast(true), on: Self.booted)

    #expect(outcome == .notApplied(IOSDisplaySettings(
      appearance: .value(.light),
      contentSize: .value(.large),
      increaseContrast: .value(false)
    )))
  }

  @Test("쓰기: 다시 읽은 그 항목이 unsupported 면 notApplied 에 unsupported 가 담긴다")
  func writeUnsupported() async throws {
    let fakeUI = FakeUI(
      ["appearance": "light", "content_size": "large", "increase_contrast": "unsupported"],
      accepts: { _, _ in false }
    )
    let command = try Self.command(ui: fakeUI)

    let outcome = try await Self.client(command).setDisplaySetting(.increaseContrast(true), on: Self.booted)

    guard case let .notApplied(read) = outcome else {
      Issue.record("notApplied 가 아니다: \(outcome)")
      return
    }
    #expect(read.increaseContrast == .unsupported)
  }

  @Test("쓰기 실패: 405 → deviceNotBooted 이고 다시 읽지 않는다, Invalid device → deviceNotFound, Unknown apperance → commandFailed")
  func writeFailure() async throws {
    let notBooted = CommandClientFake { _ in .failure(149, Self.notBootedStderr) }
    await #expect(throws: SimulatorError.deviceNotBooted) {
      try await Self.client(notBooted).setDisplaySetting(.appearance(.dark), on: Self.booted)
    }
    #expect(notBooted.invocations.map(\.arguments) == [["simctl", "ui", Self.udid, "appearance", "dark"]])

    let invalid = CommandClientFake { _ in .failure(148, "Invalid device: \(Self.udid)\n") }
    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.client(invalid).setDisplaySetting(.appearance(.dark), on: Self.booted)
    }

    let unknown = CommandClientFake { _ in .failure(1, "Unknown apperance: blue\n") }
    await #expect(throws: SimulatorError.commandFailed) {
      try await Self.client(unknown).setDisplaySetting(.appearance(.dark), on: Self.booted)
    }
  }
}

extension SimulatorClientImplConditionsTests {
  // MARK: - 위치

  @Test("위치: point·route·clear 는 목록 없이 명령 하나, provider 한 번")
  func locationCommands() async throws {
    let command = try Self.command(ui: FakeUI())
    let counter = ProviderCounter(returning: Self.developer)
    let client = Self.client(command, provider: counter)
    let point = try #require(GeoCoordinate(latitude: -33.8688, longitude: 151.2093))
    let route = try LocationRoute(
      waypoints: LocationRoute.parseWaypoints("-33.8688,151.2093\n-33.87,151.21").get(),
      speed: .walking
    )

    #expect(try await client.simulateLocation(.point(point), on: Self.booted) == .applied)
    #expect(try await client.simulateLocation(.route(route), on: Self.booted) == .applied)
    #expect(try await client.simulateLocation(.clear, on: Self.booted) == .applied)

    #expect(command.invocations.map(\.arguments) == [
      ["simctl", "location", Self.udid, "set", "-33.8688,151.2093"],
      ["simctl", "location", Self.udid, "start", "--speed=1.4", "--", "-33.8688,151.2093", "-33.87,151.21"],
      ["simctl", "location", Self.udid, "clear"],
    ])
    #expect(command.invocations.allSatisfy { $0.environment["DEVELOPER_DIR"] == "/X/Xcode.app/Contents/Developer/" })
    #expect(counter.calls == 3)
  }

  @Test("시나리오: 켜진 기기는 목록 뒤에 run (provider 한 번)")
  func scenarioBooted() async throws {
    let command = try Self.command(ui: FakeUI())
    let counter = ProviderCounter(returning: Self.developer)

    let outcome = try await Self.client(command, provider: counter)
      .simulateLocation(.scenario(.cityBicycleRide), on: Self.booted)

    #expect(outcome == .applied)
    #expect(command.invocations.map(\.arguments) == [
      Self.list,
      ["simctl", "location", Self.udid, "run", "City Bicycle Ride"],
    ])
    #expect(counter.calls == 1)
  }

  @Test("시나리오: 꺼진 기기는 run 없이 deviceNotBooted, 목록에 없으면 deviceNotFound")
  func scenarioPrecheck() async throws {
    let command = try Self.command(ui: FakeUI())

    await #expect(throws: SimulatorError.deviceNotBooted) {
      try await Self.client(command).simulateLocation(.scenario(.cityRun), on: Self.shutdown)
    }
    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.client(command).simulateLocation(.scenario(.cityRun), on: Self.missing)
    }
    #expect(command.invocations.map(\.arguments) == [Self.list, Self.list])
  }

  @Test("시나리오: Could not find scenario (exit 1, stderr) → scenarioUnavailable")
  func scenarioUnavailable() async throws {
    let fixture = try Fixture.data("simctl-list")
    let command = CommandClientFake { invocation in
      invocation.arguments == Self.list ? .success(fixture) : .failure(1, "Could not find scenario 'Apple'\n")
    }

    #expect(try await Self.client(command).simulateLocation(.scenario(.apple), on: Self.booted) == .scenarioUnavailable)
  }

  @Test(
    "위치 실패: 405 → deviceNotBooted, Invalid device → deviceNotFound, 그 밖(point 의 시나리오 문구 포함) commandFailed"
  )
  func locationFailure() async throws {
    let point = try #require(GeoCoordinate(latitude: 1, longitude: 2))
    let cases: [(CommandResult, SimulatorError)] = [
      (.failure(149, Self.notBootedStderr), .deviceNotBooted),
      (.failure(148, "Invalid device: \(Self.udid)\n"), .deviceNotFound),
      (.failure(1, "Invalid latitude,longitude pair: 1\n"), .commandFailed),
      (.failure(1, "Could not find scenario 'x'\n"), .commandFailed),
      (.failure(1, "xcrun: error: missing DEVELOPER_DIR path: /nonexistent\n"), .developerToolsUnavailable),
    ]
    for (result, expected) in cases {
      let command = CommandClientFake { _ in result }
      await #expect(throws: expected) {
        try await Self.client(command).simulateLocation(.point(point), on: Self.booted)
      }
    }
  }

  // MARK: - 공통

  @Test("UDID 형식이 아니면 provider·프로세스 없이 deviceNotFound", arguments: ["", "-h", "booted"])
  func invalidUDID(raw: String) async throws {
    let command = CommandClientFake { _ in .success() }
    let counter = ProviderCounter(returning: Self.developer)
    let client = Self.client(command, provider: counter)
    let id = VirtualDevice.ID(raw)

    await #expect(throws: SimulatorError.deviceNotFound) { try await client.displaySettings(on: id) }
    await #expect(throws: SimulatorError.deviceNotFound) {
      try await client.setDisplaySetting(.appearance(.dark), on: id)
    }
    await #expect(throws: SimulatorError.deviceNotFound) { try await client.simulateLocation(.clear, on: id) }
    #expect(command.invocations.isEmpty)
    #expect(counter.calls == 0)
  }

  @Test("provider 가 nil 이면 프로세스 없이 developerToolsUnavailable, 프로세스를 띄우지 못해도 developerToolsUnavailable")
  func noXcode() async throws {
    let command = CommandClientFake { _ in .success() }
    let client = Self.client(command, provider: ProviderCounter(returning: nil))
    await #expect(throws: SimulatorError.developerToolsUnavailable) { try await client.displaySettings(on: Self.booted)
    }
    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await client.simulateLocation(.clear, on: Self.booted)
    }
    #expect(command.invocations.isEmpty)

    let failing = CommandClientFake { _ throws(CommandError) in throw .launchFailed }
    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(failing).setDisplaySetting(.appearance(.dark), on: Self.booted)
    }
  }

  private static func command(ui fakeUI: FakeUI) throws -> CommandClientFake {
    let fixture = try Fixture.data("simctl-list")
    return CommandClientFake { invocation in
      if invocation.arguments == Self.list {
        return .success(fixture)
      }
      return fakeUI.respond(invocation.arguments) ?? .success()
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
