import LauncherFeature
import SwiftUI

/// App 없이 Launcher 화면만 띄우는 데모 앱. Preview 도 여기에 둔다.
/// Client 를 쓰게 되면 Testing 모듈의 Fake 를 주입한다.
@main
struct LauncherFeatureExampleApp: App {
  @State private var model = LauncherModel()

  var body: some Scene {
    WindowGroup {
      LauncherView(model: self.model)
    }
  }
}

#Preview("처음") {
  LauncherView(model: LauncherModel())
}
