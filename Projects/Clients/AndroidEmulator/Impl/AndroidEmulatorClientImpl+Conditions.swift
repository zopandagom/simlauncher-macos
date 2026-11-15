import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation

// MARK: - 테스트 조건 (외관·위치·런타임 권한)

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

  @concurrent
  func runtimePermissions(
    of package: AndroidPackageName,
    on id: AndroidVirtualDevice.ID
  ) async throws(AndroidEmulatorError) -> AndroidAppPermissions {
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let serial = try await self.bootedSerial(id, tools: tools)
    return try await self.readRuntimePermissions(of: package, serial: serial, tools: tools)
  }

  /// grant 또는 revoke 의 해석(`ADBPermissionCommands.parseChange`)이 `.appNotInstalled` 면 다시 읽지 않고 `.appNotInstalled`.
  /// 거부는 그 뒤 플래그를 지운다. 플래그 지우기는 해석 결과가 `.deviceNotBooted` 일 때만 던지고 그 밖의 해석 결과는 무시한다
  /// (미설치·미선언에도 exit 0 이라 정상 흐름에서 실패하지 않는다, 실측. 남는 것은 "다시 묻지 않음" 표시뿐이고 다음 거부에서 다시
  /// 지운다). 명령 실행 자체의 실패(adb 없음·시간 초과·취소)는 던진다.
  @concurrent
  func setRuntimePermission(
    _ permission: AndroidRuntimePermission,
    granted: Bool,
    of package: AndroidPackageName,
    on id: AndroidVirtualDevice.ID
  ) async throws(AndroidEmulatorError) -> AndroidPermissionOutcome {
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let serial = try await self.bootedSerial(id, tools: tools)
    let change = granted
      ? ADBPermissionCommands.grantArguments(serial: serial, package: package, permission: permission)
      : ADBPermissionCommands.revokeArguments(serial: serial, package: package, permission: permission)
    let changed = try await self.runApp(change, tools: tools)
    if try ADBPermissionCommands.parseChange(changed).get() == .appNotInstalled {
      return .appNotInstalled
    }
    if !granted {
      let cleared = try await self.runApp(
        ADBPermissionCommands.clearFlagsArguments(serial: serial, package: package, permission: permission),
        tools: tools
      )
      if case .failure(.deviceNotBooted) = ADBPermissionCommands.parseChange(cleared) {
        throw .deviceNotBooted
      }
    }
    switch try await self.readRuntimePermissions(of: package, serial: serial, tools: tools) {
    case .appNotInstalled:
      return .appNotInstalled
    case let .runtime(grants):
      let applied = grants.contains { $0.permission == permission && $0.isGranted == granted }
      return applied ? .applied(grants) : .notApplied(grants)
    }
  }
}

extension AndroidEmulatorClientImpl {
  private func readRuntimePermissions(
    of package: AndroidPackageName,
    serial: String,
    tools: SDKTools
  ) async throws(AndroidEmulatorError) -> AndroidAppPermissions {
    let result = try await self.runApp(
      ADBPermissionCommands.dumpsysPackageArguments(serial: serial, package: package),
      tools: tools
    )
    return try ADBPermissionCommands.parseRuntimePermissions(result, package: package).get()
  }
}
