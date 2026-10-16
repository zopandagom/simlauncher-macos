import HomeFeature
import SwiftUI

/// App 없이 Home 화면만 띄우는 데모 앱. Preview 도 여기에 둔다.
/// Client 를 쓰게 되면 Testing 모듈의 Fake 를 주입한다.
@main
struct HomeFeatureExampleApp: App {
  @State private var model = HomeModel()

  var body: some Scene {
    WindowGroup {
      HomeView(model: self.model)
    }
  }
}

#Preview("처음") {
  HomeView(model: HomeModel())
}
