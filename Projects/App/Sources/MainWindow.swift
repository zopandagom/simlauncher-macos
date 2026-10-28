import AndroidSetupFeature
import LauncherFeature
import SetupFeature
import SwiftUI

/// 메인 창. 사이드바로 iOS / Android 칸을 나눈다.
/// iOS 칸은 Setup 이 끝나면(`SetupModel.isFinished`) 기기 목록, 아니면 Setup 이다. Android 칸은 Xcode 준비 여부와 관계없이
/// Android 도구 화면이다. 칸을 옮기면 떠난 칸의 View 가 사라지고, 돌아오면 새로 만들어져 `onAppear` 가 다시 읽는다
/// (계획 받기·설치·녹화 같은 진행은 Model 이 소유해 계속된다). 고른 칸은 View 일시 상태라 앱을 다시 켜면 iOS 칸이다.
struct MainWindow: View {
  let setupModel: SetupModel
  let launcherModel: LauncherModel
  let catalogInstallModel: CatalogInstallModel
  let androidSetupModel: AndroidSetupModel
  @State private var platform: Platform = .iOS

  /// 사이드바 항목. 이름("iOS"·"Android")은 고유 이름이라 카탈로그를 거치지 않는다 (App 에는 String Catalog 가 없다).
  enum Platform: Hashable, CaseIterable {
    case iOS, android

    var title: String {
      switch self {
      case .iOS: "iOS"
      case .android: "Android"
      }
    }

    var systemImage: String {
      switch self {
      case .iOS: "iphone"
      case .android: "smartphone"
      }
    }
  }

  var body: some View {
    NavigationSplitView {
      List(
        Platform.allCases,
        id: \.self,
        selection: Binding(get: { Optional(self.platform) }, set: { self.platform = $0 ?? self.platform })
      ) { platform in
        Label {
          Text(verbatim: platform.title)
        } icon: {
          Image(systemName: platform.systemImage)
        }
      }
      .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 220)
    } detail: {
      switch self.platform {
      case .iOS:
        // 기기 목록 화면은 Setup 이 끝나야 만들어진다 (그 전에는 목록 읽기·정리가 돌지 않는다).
        // 돌아올 때마다 새로 만들어져 onAppear 가 목록을 다시 읽는다.
        if self.setupModel.isFinished {
          LauncherView(model: self.launcherModel, catalogModel: self.catalogInstallModel)
        } else {
          SetupView(model: self.setupModel)
        }
      case .android:
        AndroidSetupView(model: self.androidSetupModel)
      }
    }
  }
}
