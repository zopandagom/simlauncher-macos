import AndroidDevicesFeature
import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core

/// "테스트 조건" 장면의 Fake 설정. 켜진 기기("Pixel Tablet")의 "테스트 조건…" 을 누른다.
enum DemoTestConditions {
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
