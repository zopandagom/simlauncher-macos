import AndroidDevicesFeature
import AndroidSetupFeature
import LauncherFeature
import SetupFeature
import SwiftUI
import UpdateFeature

/// 메인 창. 사이드바로 iOS / Android 칸을 나눈다.
/// iOS 칸은 Setup 이 끝나면(`SetupModel.isFinished`) 기기 목록, 아니면 Setup 이다. Android 칸은 Xcode 준비 여부와 관계없이
/// 열리고, 도구 화면에서 기기 목록으로 넘어가면(`AndroidSetupModel.isFinished`: 첫 확인이 셋 다 설치됨이거나 "기기 목록 열기")
/// Android 기기 목록, 아니면 Android 도구 화면이다. 칸을 옮기면 떠난 칸의 View 가 사라지고, 돌아오면 새로 만들어져 `onAppear` 가 다시 읽는다
/// (계획 받기·설치·녹화 같은 진행은 Model 이 소유해 계속된다). 고른 칸은 View 일시 상태라 앱을 다시 켜면 iOS 칸이다.
/// 새 버전 배너(`UpdateBanner`)는 detail 위쪽에 붙어 iOS·Android 칸, Setup·기기 목록 화면 모두 위에 보인다.
struct MainWindow: View {
  let setupModel: SetupModel
  let launcherModel: LauncherModel
  let catalogInstallModel: CatalogInstallModel
  let launcherAppSheetsModel: LauncherAppSheetsModel
  let testConditionsModel: TestConditionsModel
  let installedAppsModel: InstalledAppsModel
  let androidSetupModel: AndroidSetupModel
  let androidDevicesModel: AndroidDevicesModel
  let androidDownloadInstallModel: AndroidDownloadInstallModel
  let androidAppSheetsModel: AndroidAppSheetsModel
  let androidTestConditionsModel: AndroidTestConditionsModel
  let androidInstalledAppsModel: AndroidInstalledAppsModel
  let updateModel: UpdateModel
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
      self.detail
        .safeAreaInset(edge: .top, spacing: 0) {
          UpdateBanner(model: self.updateModel)
        }
        .frame(minWidth: Self.detailMinWidth)
    }
  }

  /// detail 의 최소 폭. 기기 행(`DeviceRow`·`AndroidDeviceRow`)의 글자 버튼은 줄어들지 않으므로, 영어에서 버튼 영역이 가장 넓은
  /// 녹화 중 행(앱 설치·앱 실행·로그 보기·경과 시간·중지·끄기·⋯ 약 593pt)과 이름 열 최소 폭·여백(약 220pt)이 잘리지 않는 폭이다.
  /// 이 때문에 창의 최소 폭은 사이드바를 더해 약 960~980pt 다.
  private static let detailMinWidth: CGFloat = 820

  @ViewBuilder
  private var detail: some View {
    switch self.platform {
    case .iOS:
      // 기기 목록 화면은 Setup 이 끝나야 만들어진다 (그 전에는 목록 읽기·정리가 돌지 않는다).
      // 돌아올 때마다 새로 만들어져 onAppear 가 목록을 다시 읽는다.
      if self.setupModel.isFinished {
        LauncherView(
          model: self.launcherModel,
          catalogModel: self.catalogInstallModel,
          appSheetsModel: self.launcherAppSheetsModel,
          conditionsModel: self.testConditionsModel,
          installedAppsModel: self.installedAppsModel
        )
      } else {
        SetupView(model: self.setupModel)
      }
    case .android:
      // 기기 목록 화면은 Android 도구 첫 확인이 셋 다 설치됨이거나 "기기 목록 열기" 뒤에 만들어진다 (그 전에는 목록 읽기·adb 가
      // 돌지 않는다). 돌아올 때마다 새로 만들어져 onAppear 가 목록을 다시 읽는다.
      if self.androidSetupModel.isFinished {
        AndroidDevicesView(
          model: self.androidDevicesModel,
          downloadModel: self.androidDownloadInstallModel,
          appSheetsModel: self.androidAppSheetsModel,
          conditionsModel: self.androidTestConditionsModel,
          installedAppsModel: self.androidInstalledAppsModel
        )
      } else {
        AndroidSetupView(model: self.androidSetupModel)
      }
    }
  }
}
