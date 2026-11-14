import CommandInterface
import Core
import Foundation
import SimulatorInterface

// MARK: - 테스트 조건 (화면 설정 읽기·쓰기, 위치)

public extension SimulatorClientImpl {
  /// 셋이 모두 `.unknown` 일 때만 목록을 읽어 꺼짐을 가린다 (꺼진 기기의 읽기는 exit 0 `unknown`, 실측).
  func displaySettings(on id: VirtualDevice.ID) async throws(SimulatorError) -> IOSDisplaySettings {
    guard let udid = SimctlCommand.validatedUDID(id.rawValue) else {
      throw .deviceNotFound
    }
    let directory = try await self.resolveDeveloperDirectory()
    let settings = try await self.readDisplaySettings(udid, developerDirectory: directory)
    if SimctlUIParser.isAllUnknown(settings) {
      try await self.requireBootedDevice(udid, developerDirectory: directory)
    }
    return settings
  }

  /// 쓰기가 0 이 아닌 종료 코드면 다시 읽지 않는다. 다시 읽은 값이 셋 다 `.unknown` 이어도 목록은 읽지 않는다
  /// (바로 앞 쓰기가 성공했으므로 켜져 있었다. 결과는 `.notApplied` 다).
  func setDisplaySetting(
    _ setting: IOSDisplaySetting,
    on id: VirtualDevice.ID
  ) async throws(SimulatorError) -> IOSDisplaySettingOutcome {
    guard let udid = SimctlCommand.validatedUDID(id.rawValue) else {
      throw .deviceNotFound
    }
    let directory = try await self.resolveDeveloperDirectory()
    let (option, value) = SimctlUIParser.write(setting)
    let result = try await self.runSimctl(SimctlCommand.uiWrite(udid: udid, option: option, value: value), directory)
    guard result.exitCode == 0 else {
      throw SimctlErrorClassifier.bootedDeviceCommandError(exitCode: result.exitCode, stderr: Self.stderr(result))
    }
    let read = try await self.readDisplaySettings(udid, developerDirectory: directory)
    return SimctlUIParser.outcome(of: setting, read: read)
  }

  /// 시나리오만 실행 전에 목록을 읽는다 (꺼진 기기에서 `run` 은 405 가 아니라 `Could not find scenario`, 실측).
  func simulateLocation(
    _ simulation: IOSLocationSimulation,
    on id: VirtualDevice.ID
  ) async throws(SimulatorError) -> IOSLocationOutcome {
    guard let udid = SimctlCommand.validatedUDID(id.rawValue) else {
      throw .deviceNotFound
    }
    let directory = try await self.resolveDeveloperDirectory()
    let arguments: [String]
    switch simulation {
    case let .point(coordinate):
      arguments = SimctlCommand.locationSet(udid: udid, coordinate: coordinate)
    case let .route(route):
      arguments = SimctlCommand.locationStart(udid: udid, route: route)
    case let .scenario(scenario):
      try await self.requireBootedDevice(udid, developerDirectory: directory)
      arguments = SimctlCommand.locationRun(udid: udid, scenario: scenario.rawValue)
    case .clear:
      arguments = SimctlCommand.locationClear(udid: udid)
    }
    let result = try await self.runSimctl(arguments, directory)
    guard result.exitCode == 0 else {
      let stderr = Self.stderr(result)
      if
        case .scenario = simulation,
        SimctlCommand.scenarioNotFound(exitCode: result.exitCode, output: Self.stderr(result.stdout) + "\n" + stderr)
      {
        return .scenarioUnavailable
      }
      throw SimctlErrorClassifier.bootedDeviceCommandError(exitCode: result.exitCode, stderr: stderr)
    }
    return .applied
  }
}

extension SimulatorClientImpl {
  /// `ui` 읽기 세 번 (appearance → content_size → increase_contrast, 같은 디렉터리). 하나라도 0 이 아니면 분류해 던진다.
  func readDisplaySettings(
    _ udid: String,
    developerDirectory: URL?
  ) async throws(SimulatorError) -> IOSDisplaySettings {
    let appearance = try await self.readUI(udid, .appearance, developerDirectory)
    let contentSize = try await self.readUI(udid, .contentSize, developerDirectory)
    let increaseContrast = try await self.readUI(udid, .increaseContrast, developerDirectory)
    return IOSDisplaySettings(
      appearance: SimctlUIParser.appearance(appearance),
      contentSize: SimctlUIParser.contentSize(contentSize),
      increaseContrast: SimctlUIParser.increaseContrast(increaseContrast)
    )
  }

  private func readUI(
    _ udid: String,
    _ option: SimctlUIOption,
    _ directory: URL?
  ) async throws(SimulatorError) -> Data {
    let result = try await self.runSimctl(SimctlCommand.uiRead(udid: udid, option: option), directory)
    guard result.exitCode == 0 else {
      throw SimctlErrorClassifier.bootedDeviceCommandError(exitCode: result.exitCode, stderr: Self.stderr(result))
    }
    return result.stdout
  }

  private func runSimctl(_ arguments: [String], _ directory: URL?) async throws(SimulatorError) -> CommandResult {
    try await self.run(
      SimctlCommand.xcrun,
      arguments,
      developerDirectory: directory,
      launchFailure: .developerToolsUnavailable
    )
  }
}
