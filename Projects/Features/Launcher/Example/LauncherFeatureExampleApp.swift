import Core
import LauncherFeature
import SimulatorTesting
import SwiftUI

/// App 없이 Launcher 화면만 띄우는 데모 앱. Preview 도 여기에 둔다.
/// 실제 시뮬레이터 대신 Testing 모듈의 `SimulatorClientFake`(샘플 목록, 호출마다 1초 지연)를 주입한다.
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
    return LauncherModel(simulator: fake)
  }
}

/// Fake 를 만들어 설정한 뒤 화면을 만든다.
@MainActor
private func previewLauncher(
  _ inventory: DeviceInventory = .sample,
  configure: (SimulatorClientFake) -> Void = { _ in }
) -> LauncherView {
  let fake = SimulatorClientFake(inventory: inventory)
  configure(fake)
  return LauncherView(model: LauncherModel(simulator: fake))
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

#Preview("켜기 실패 (꺼진 기기의 켜기를 누른다)") {
  previewLauncher { $0.setBootError(.commandFailed) }
}
