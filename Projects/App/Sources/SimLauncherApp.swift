import LauncherFeature
import SimulatorImpl
import SwiftUI

/// 조립 지점. Client Impl 을 만들어 Feature Model 에 주입하는 곳은 여기뿐이다.
@main
struct SimLauncherApp: App {
  // 개발자 디렉터리는 xcode-select 가 고른 것을 쓴다 (provider nil). 3단계에서 DevEnvironment 의 provider 로 바꾼다.
  @State private var launcherModel = LauncherModel(simulator: SimulatorClientImpl(developerDirectory: nil))

  var body: some Scene {
    WindowGroup {
      LauncherView(model: self.launcherModel)
    }
  }
}
