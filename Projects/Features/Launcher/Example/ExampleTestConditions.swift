import Core
import LauncherFeature
import SimulatorInterface
import SimulatorTesting
import SwiftUI

// 테스트 조건·설치된 앱 시트 연결 (App 의 조립과 같다)과 시트 상태 미리보기. `LauncherFeatureExampleApp.swift` 가 600 줄에 닿아
// 나눴다.

/// Example 앱이 `@State` 로 갖는 Model 묶음.
struct ExampleModels {
  let launcher: LauncherModel
  let appSheets: LauncherAppSheetsModel
  let conditions: TestConditionsModel
  let installedApps: InstalledAppsModel

  /// App 처럼 테스트 조건·설치된 앱 시트 Model 을 기기 목록에 잇고, 기기 목록이 읽는 상자에 세 시트 Model 을 넣는다.
  @MainActor
  init(
    launcher: LauncherModel,
    appSheets: LauncherAppSheetsModel,
    simulator: SimulatorClientFake,
    box: ExampleAppSheetsBox
  ) {
    self.launcher = launcher
    self.appSheets = appSheets
    self.conditions = makeConditionsModel(simulator: simulator, launcher: launcher)
    self.installedApps = InstalledAppsModel(
      simulator: simulator,
      target: { launcher.installedAppsTarget($0) },
      refreshRequested: { await launcher.refreshButtonTapped() }
    )
    box.model = appSheets
    box.conditions = self.conditions
    box.installedApps = self.installedApps
  }
}

/// App 처럼 테스트 조건 시트 Model 을 기기 목록에 잇는다 (열 기기·다시 읽기는 `launcher`).
@MainActor
func makeConditionsModel(simulator: SimulatorClientFake, launcher: LauncherModel) -> TestConditionsModel {
  TestConditionsModel(
    simulator: simulator,
    target: { launcher.testConditionsTarget($0) },
    refreshRequested: { await launcher.refreshButtonTapped() }
  )
}

/// 기기 목록 Model 이 뒤에 만든 시트 Model 들을 읽게 넘기는 상자 (App 의 `LauncherAppSheetsBox` 와 같다).
@MainActor
final class ExampleAppSheetsBox {
  weak var model: LauncherAppSheetsModel?
  weak var conditions: TestConditionsModel?
  weak var installedApps: InstalledAppsModel?

  var hasPresentedSheet: Bool {
    (self.model?.hasPresentedSheet ?? false) || (self.conditions?.hasPresentedSheet ?? false)
      || (self.installedApps?.hasPresentedSheet ?? false)
  }
}

// MARK: - 테스트 조건 미리보기

// 테스트 조건 시트의 상태 미리보기. 켜진 기기 행의 "테스트 조건…" 을 누른다.
// 읽는 중·적용 중은 Fake 지연으로, 그 밖의 상태는 Fake 설정으로 만든다.

#Preview("테스트 조건: 읽는 중·적용 중 (2초씩 걸린다)") {
  previewLauncher { $0.setDelay(.seconds(2)) }
}

#Preview("테스트 조건: 지금 값을 읽지 못함 (다시 읽기)") {
  previewLauncher { $0.setDisplaySettingsError(.commandFailed) }
}

#Preview("테스트 조건: 지원 안 함·알 수 없음 (고대비 지원 안 함, 글씨 크기 알 수 없음)") {
  previewLauncher { fake in
    for device in DeviceInventory.sample.devices {
      fake.setDisplaySettings(
        IOSDisplaySettings(appearance: .value(.dark), contentSize: .unknown, increaseContrast: .unsupported),
        for: device.id
      )
    }
  }
}

#Preview("테스트 조건: 적용 안 됨 (외관을 바꾸면 다시 읽은 값이 그대로다)") {
  previewLauncher { $0.setDisplaySettingNotApplied(SimulatorClientFake.defaultDisplaySettings) }
}

#Preview("테스트 조건: 기기 꺼짐 (바꾸거나 위치를 보내면 실패)") {
  previewLauncher { fake in
    fake.setDisplaySettingError(.deviceNotBooted)
    fake.setLocationError(.deviceNotBooted)
  }
}

#Preview("테스트 조건: 시나리오 없음 (시나리오 실행)") {
  previewLauncher { $0.setScenarioUnavailable(true) }
}

// MARK: - 앱 단위 구역 미리보기

// 앱 구역에서 앱을 고른 뒤 권한·푸시 알림을 해 본다.

#Preview("테스트 조건 앱: 앱 목록을 읽지 못함 (다시 읽기)") {
  previewLauncher { $0.setInstalledAppsError(.commandFailed) }
}

#Preview("테스트 조건 앱: 설치한 앱 없음") {
  previewLauncher { ExampleInstalledApps.install(on: $0, apps: []) }
}

#Preview("테스트 조건 앱: 앱 하나 (자동으로 고름)") {
  previewLauncher { ExampleInstalledApps.install(on: $0, apps: [ExampleInstalledApps.all[0]]) }
}

#Preview("테스트 조건 앱: 권한·푸시가 기기 꺼짐으로 실패") {
  previewLauncher { fake in
    fake.setPrivacyError(.deviceNotBooted)
    fake.setPushError(.deviceNotBooted)
  }
}

#Preview("테스트 조건 앱: 푸시 알림 권한 없음 (iOS 27)") {
  previewLauncher { $0.setPushOutcome(.notAuthorized) }
}

#Preview("테스트 조건 앱: 푸시 보일 내용 없음 (iOS 27)") {
  previewLauncher { $0.setPushOutcome(.noVisibleContent) }
}

#Preview("테스트 조건 앱: 푸시 내용 거절") {
  previewLauncher { $0.setPushOutcome(.payloadRejected) }
}

// MARK: - 설치된 앱 미리보기

// 설치된 앱 시트의 상태 미리보기. 켜진 기기 행의 "설치된 앱…" 을 누른다. Fake 는 지워도 목록을 바꾸지 않아, 지운 뒤 다시 읽은
// 목록에 그 앱이 다시 보인다 (지운 직후의 결과 줄과 목록에서 빠지는 모습만 본다).

#Preview("설치된 앱: 읽는 중·지우는 중 (2초씩 걸린다)") {
  previewLauncher { $0.setDelay(.seconds(2)) }
}

#Preview("설치된 앱: 앱 목록을 읽지 못함 (다시 읽기)") {
  previewLauncher { $0.setInstalledAppsError(.commandFailed) }
}

#Preview("설치된 앱: 설치한 앱 없음") {
  previewLauncher { ExampleInstalledApps.install(on: $0, apps: []) }
}

#Preview("설치된 앱: 지우기가 기기 꺼짐으로 실패 (목록 실패·기기 목록 다시 읽기)") {
  previewLauncher { $0.setUninstallError(.deviceNotBooted) }
}

#Preview("설치된 앱: 지우기가 명령 실패 (결과 줄·목록 다시 읽기)") {
  previewLauncher { $0.setUninstallError(.commandFailed) }
}
