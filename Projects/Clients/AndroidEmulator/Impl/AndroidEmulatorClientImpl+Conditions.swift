import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation

// MARK: - 테스트 조건 (외관·위치)

public extension AndroidEmulatorClientImpl {
  /// 위치 서비스 읽기의 실패(취소 제외)는 nil 로 둔다.
  @concurrent
  func testConditions(on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) -> AndroidTestConditions {
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let serial = try await self.bootedSerial(id, tools: tools)
    let night = try await self.runApp(ADBConditionCommands.nightModeReadArguments(serial: serial), tools: tools)
    let nightMode = try ADBConditionCommands.parseNightModeRead(night).get()
    let locationEnabled: Bool?
    do throws(AndroidEmulatorError) {
      let result = try await self.runApp(ADBConditionCommands.locationEnabledArguments(serial: serial), tools: tools)
      locationEnabled = ADBConditionCommands.parseLocationEnabled(result)
    } catch .cancelled {
      throw .cancelled
    } catch {
      locationEnabled = nil
    }
    return AndroidTestConditions(nightMode: nightMode, locationEnabled: locationEnabled)
  }

  @concurrent
  func setNightMode(
    _ appearance: DeviceAppearance,
    on id: AndroidVirtualDevice.ID
  ) async throws(AndroidEmulatorError) -> AndroidConditionOutcome {
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let serial = try await self.bootedSerial(id, tools: tools)
    let written = try await self.runApp(
      ADBConditionCommands.nightModeWriteArguments(serial: serial, appearance: appearance),
      tools: tools
    )
    if let outcome = try ADBConditionCommands.parseNightModeWrite(written, requested: appearance).get() {
      return outcome
    }
    // 쓰기 출력에 `Night mode:` 줄이 없다: 한 번 다시 읽어 판정한다.
    let read = try await self.runApp(ADBConditionCommands.nightModeReadArguments(serial: serial), tools: tools)
    let reading = try ADBConditionCommands.parseNightModeRead(read).get()
    return ADBConditionCommands.matches(reading, appearance) ? .applied : .notApplied
  }

  @concurrent
  func setLocation(
    _ coordinate: GeoCoordinate,
    on id: AndroidVirtualDevice.ID
  ) async throws(AndroidEmulatorError) -> AndroidConditionOutcome {
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let serial = try await self.bootedSerial(id, tools: tools)
    let result = try await self.runApp(
      ADBConditionCommands.geoFixArguments(serial: serial, coordinate: coordinate),
      tools: tools
    )
    return try ADBConditionCommands.parseGeoFix(result).get()
  }
}
