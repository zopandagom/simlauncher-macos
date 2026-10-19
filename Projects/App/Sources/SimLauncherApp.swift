import AppBundleImpl
import CommandImpl
import LauncherFeature
import SimulatorImpl
import SwiftUI

/// 조립 지점. Client Impl 을 만들어 Feature Model 에 주입하는 곳은 여기뿐이다.
@main
struct SimLauncherApp: App {
  @State private var launcherModel = Self.makeLauncherModel()

  var body: some Scene {
    WindowGroup {
      LauncherView(model: self.launcherModel)
    }
  }

  /// 명령 실행 Client 하나를 시뮬레이터·앱 번들 Client 가 함께 쓴다.
  private static func makeLauncherModel() -> LauncherModel {
    let command = CommandClientImpl()
    // 개발자 디렉터리는 xcode-select 가 고른 것을 쓴다 (provider nil). 3단계에서 DevEnvironment 의 provider 로 바꾼다.
    return LauncherModel(
      simulator: SimulatorClientImpl(developerDirectory: nil, command: command),
      appBundle: AppBundleClientImpl(command: command)
    )
  }
}
