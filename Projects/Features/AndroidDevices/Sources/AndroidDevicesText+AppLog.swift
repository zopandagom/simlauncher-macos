import Foundation

/// 앱 로그 문구: 행 "로그 보기" 버튼과 툴팁, 앱 실행 시트 안내. 모두 iOS 기기 목록(Launcher)과 같은 키·값이다
/// (Feature 끼리 공유하지 않아 따로 두고 `LauncherTextSyncTests` 가 묶는다). 키는 다른 문구와 같은 `Localizable.xcstrings` 에 있다.
extension AndroidDevicesText {
  static var viewLogButton: String {
    String(localized: "로그 보기", bundle: .module)
  }

  static var viewLogHelp: String {
    String(localized: "이 기기에서 실행한 앱의 로그 창을 엽니다", bundle: .module)
  }

  static var viewLogUnavailableHelp: String {
    String(localized: "앱 실행… 이나 앱 설치로 SimLauncher 가 이 기기에서 앱을 실행하면 로그를 볼 수 있습니다", bundle: .module)
  }

  /// 앱 실행 시트에서 목록을 읽었을 때 목록 아래에 보인다.
  static var launchAppSheetNote: String {
    String(
      localized: "이미 실행 중이면 끝내고 다시 실행합니다. 실행한 뒤 로그 보기로 앱 로그를 볼 수 있습니다.",
      bundle: .module
    )
  }
}
