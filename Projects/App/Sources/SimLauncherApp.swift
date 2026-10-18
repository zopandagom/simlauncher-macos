import LauncherFeature
import SwiftUI

/// 조립 지점. Client Impl 을 만들어 Feature Model 에 주입하는 곳은 여기뿐이다.
@main
struct SimLauncherApp: App {
  @State private var launcherModel = LauncherModel()

  var body: some Scene {
    WindowGroup {
      LauncherView(model: self.launcherModel)
    }
  }
}
