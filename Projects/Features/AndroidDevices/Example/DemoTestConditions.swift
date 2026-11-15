import AndroidDevicesFeature
import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core

/// "테스트 조건" 장면의 Fake 설정. 켜진 기기("Pixel Tablet")의 "테스트 조건…" 을 누른다.
enum DemoTestConditions {
  /// 모든 장면에서 켜진 기기의 샘플 앱 권한: `com.example.sample` 은 알려진 권한·모르는 권한을 섞어 요청하고, `org.example.shop` 은
  /// 바꿀 수 있는 권한을 요청하지 않는다.
  static func installPermissions(on fake: AndroidEmulatorClientFake) {
    let id = AndroidVirtualDevice.bootedTabletSample.id
    let sample: [(String, Bool)] = [
      ("android.permission.BLUETOOTH_CONNECT", false),
      ("android.permission.CAMERA", false),
      ("android.permission.ACCESS_FINE_LOCATION", true),
      ("android.permission.ACCESS_COARSE_LOCATION", true),
      ("android.permission.POST_NOTIFICATIONS", false),
    ]
    let grants = sample.compactMap { raw, granted in
      AndroidRuntimePermission(raw).map { AndroidPermissionGrant(permission: $0, isGranted: granted) }
    }
    if let package = AndroidPackageName("com.example.sample") {
      fake.setRuntimePermissions(grants, of: package, on: id)
    }
    if let package = AndroidPackageName("org.example.shop") {
      fake.setRuntimePermissions([], of: package, on: id)
    }
  }

  static func configure(_ fake: AndroidEmulatorClientFake, for scenario: DemoScenario) {
    switch scenario {
    case .conditionsReadFailure:
      fake.setTestConditionsError(.adbUnavailable)
    case .conditionsOther:
      fake.setTestConditions(
        AndroidTestConditions(nightMode: .other, locationEnabled: false),
        for: AndroidVirtualDevice.bootedTabletSample.id
      )
    case .conditionsNotApplied:
      fake.setNightModeResult(.success(.notApplied))
      fake.setLocationResult(.success(.notApplied))
    case .conditionsDeviceOff:
      fake.setNightModeResult(.failure(.deviceNotBooted))
      fake.setLocationResult(.failure(.deviceNotBooted))
      fake.setRuntimePermissionError(.deviceNotBooted)
    case .conditionsPackagesFailure:
      fake.setInstalledPackages(.failure(.adbUnavailable))
    case .conditionsPermissionsFailure:
      fake.setRuntimePermissionsError(.adbUnavailable)
    case .conditionsPermissionNotApplied:
      fake.setRuntimePermissionNotApplied(true)
    case .conditionsAppMissing:
      // 권한을 두지 않은 패키지 하나만 있어 자동으로 고르고 "앱이 기기에 없음" 을 읽는다.
      fake.setInstalledPackages(.success([AndroidPackageName("com.example.removed")].compactMap(\.self)))
    default:
      break
    }
  }
}

extension DemoTestConditions {
  /// App 처럼 기기 목록 Model 에 이은 테스트 조건 시트 Model.
  @MainActor
  static func model(emulator: AndroidEmulatorClientFake, devices: AndroidDevicesModel) -> AndroidTestConditionsModel {
    AndroidTestConditionsModel(
      emulator: emulator,
      target: { devices.testConditionsTarget($0) },
      refreshRequested: { await devices.refreshButtonTapped() }
    )
  }
}
