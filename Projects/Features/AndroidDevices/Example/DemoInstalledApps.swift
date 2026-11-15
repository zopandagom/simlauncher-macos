import AndroidDevicesFeature
import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core

/// "설치된 앱" 장면의 Fake 설정. 켜진 기기("Pixel Tablet")의 "설치된 앱…" 을 누르고, 앱을 골라 "삭제…" 를 확인한다.
enum DemoInstalledApps {
  static func configure(_ fake: AndroidEmulatorClientFake, for scenario: DemoScenario) {
    switch scenario {
    case .installedAppsSlowRemove:
      // 지우는 동안 "닫기"·Esc 가 꺼지고 목록·다시 읽기도 꺼진 것을 본다 (끝나지 않는다).
      fake.suspendUninstalls()
    case .installedAppsRemoveFailure:
      fake.setUninstallError(.appCommandFailed)
    case .installedAppsDeviceOff:
      fake.setUninstallError(.deviceNotBooted)
    default:
      break
    }
  }

  /// App 처럼 기기 목록 Model 에 이은 설치된 앱 시트 Model. 기기 목록이 읽는 상자에도 넣는다.
  @MainActor
  static func model(
    emulator: AndroidEmulatorClientFake,
    devices: AndroidDevicesModel,
    box: DemoAppSheetsBox
  ) -> AndroidInstalledAppsModel {
    let model = AndroidInstalledAppsModel(
      emulator: emulator,
      target: { devices.installedAppsTarget($0) },
      refreshRequested: { await devices.refreshButtonTapped() }
    )
    box.installedApps = model
    return model
  }
}
