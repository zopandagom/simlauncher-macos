import AppBundleTesting
import Core
import LauncherFeature
import SimulatorTesting
import SwiftUI

/// App 없이 Launcher 화면만 띄우는 데모 앱. Preview 도 여기에 둔다.
/// 실제 시뮬레이터 대신 Testing 모듈의 `SimulatorClientFake`(샘플 목록, 호출마다 1초 지연, 링크는 켜진 기기면
/// 어떤 링크든 열린 것으로 끝난다)와 `AppBundleClientFake`(어떤 파일을 골라도 샘플 앱, zip 도 1초 풀기 뒤 샘플 앱,
/// 1초 지연)를 주입한다.
@main
struct LauncherFeatureExampleApp: App {
  @State private var model = Self.makeModel()

  var body: some Scene {
    WindowGroup {
      LauncherView(model: self.model)
    }
  }

  private static func makeModel() -> LauncherModel {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.setDelay(.seconds(1))
    let appBundle = AppBundleClientFake()
    appBundle.setDelay(.seconds(1))
    return LauncherModel(simulator: fake, appBundle: appBundle)
  }
}

/// Fake 를 만들어 설정한 뒤 화면을 만든다.
@MainActor
private func previewLauncher(
  _ inventory: DeviceInventory = .sample,
  configure: (SimulatorClientFake) -> Void = { _ in },
  appBundle configureAppBundle: (AppBundleClientFake) -> Void = { _ in }
) -> LauncherView {
  let fake = SimulatorClientFake(inventory: inventory)
  configure(fake)
  let appBundle = AppBundleClientFake()
  configureAppBundle(appBundle)
  return LauncherView(model: LauncherModel(simulator: fake, appBundle: appBundle))
}

#Preview("목록") {
  previewLauncher()
}

#Preview("불러오는 중") {
  previewLauncher { $0.suspendFetches() }
}

#Preview("불러오기 실패") {
  previewLauncher { $0.setFetchError(.developerToolsUnavailable) }
}

#Preview("런타임 없음") {
  previewLauncher(.noRuntime)
}

#Preview("기기 없음") {
  previewLauncher(.noDevices)
}

#Preview("만들 수 있는 기기 종류 없음") {
  previewLauncher(.noCreatableDeviceType)
}

#Preview("기기는 있지만 만들 수 없음") {
  previewLauncher(
    DeviceInventory(devices: DeviceInventory.sample.devices, runtimes: DeviceInventory.sample.runtimes, deviceTypes: [])
  )
}

#Preview("켜기 실패 (꺼진 기기의 켜기를 누른다)") {
  previewLauncher { $0.setBootError(.commandFailed) }
}

/// 켜기 한 번으로 알림 두 개(켜기 실패 → 다시 읽기 실패)가 쌓인다.
/// 첫 목록을 읽은 뒤 1초가 지나면 목록 읽기도 실패하게 바꾼다.
#Preview("실패 알림 두 개 (1초 뒤 꺼진 기기의 켜기를 한 번 누른다)") {
  previewLauncher { fake in
    fake.setBootError(.commandFailed)
    Task {
      try? await Task.sleep(for: .seconds(1))
      fake.setFetchError(.commandFailed)
    }
  }
}

#Preview("실패 알림 두 개 (2초 안에 켜기와 끄기를 누른다)") {
  previewLauncher {
    $0.setBootError(.commandFailed)
    $0.setShutdownError(.deviceNotFound)
    $0.setDelay(.seconds(2))
  }
}

#Preview("만들기 실패 (+ → 만들기)") {
  previewLauncher { $0.setCreateError(.creationOptionUnavailable) }
}

#Preview("만드는 중 (+ → 만들기, 끝나지 않음)") {
  previewLauncher { $0.suspendCreates() }
}

#Preview("삭제 실패 (꺼진 기기의 … → 삭제…)") {
  previewLauncher { $0.setDeleteError(.deviceNotShutdown) }
}

#Preview("초기화 실패 (꺼진 기기의 … → 초기화…)") {
  previewLauncher { $0.setEraseError(.commandFailed) }
}

#Preview("앱 설치 (꺼진 기기의 앱 설치…)") {
  previewLauncher { $0.setDelay(.seconds(1)) }
}

#Preview("설치 중 (앱 설치…, 끝나지 않음)") {
  previewLauncher { $0.suspendInstalls() }
}

#Preview("거절: 기기용 빌드 (앱 설치…)") {
  previewLauncher(appBundle: { $0.setInfo(.deviceBuild) })
}

#Preview("거절: 높은 iOS 필요 (앱 설치…)") {
  previewLauncher(appBundle: { $0.setInfo(.requiring(OSVersion(major: 99))) })
}

#Preview("zip 에 .app 없음 (앱 설치… → zip)") {
  previewLauncher(appBundle: { $0.setExtractError(.zipWithoutApp) })
}

#Preview("실행 실패 (앱 설치…)") {
  previewLauncher { $0.setLaunchError(.appLaunchFailed) }
}

#Preview("링크 열기 (켜진·꺼진 기기의 링크 열기…)") {
  previewLauncher { $0.setDelay(.seconds(1)) }
}

#Preview("링크 여는 중 (링크 열기… → 열기, 끝나지 않음)") {
  previewLauncher { $0.suspendOpenURLs() }
}

#Preview("링크 열 앱 없음 (링크 열기… → 열기)") {
  previewLauncher { $0.setOpenURLError(.urlNotHandled) }
}

/// 설치가 3초 걸려 실패하는 동안 다른 기기의 링크 시트를 열어, 설치 실패 알림과 링크 시트가 함께 나와도 깨지지 않는지 본다.
#Preview("설치 실패 중 링크 시트 (한 기기의 앱 설치… 뒤 다른 기기의 링크 열기…)") {
  previewLauncher {
    $0.setDelay(.seconds(3))
    $0.setInstallError(.appIncompatible)
  }
}
