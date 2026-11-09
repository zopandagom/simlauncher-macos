@testable import AndroidDevicesFeature

/// 앱 로그 문구(`AndroidDevicesText+AppLog.swift`·바뀐 `launchAppHelp`)의 String Catalog 키. `DownloadTextCatalog` 와 같은 방식으로
/// `AndroidDevicesResourcesTests` 는 이 모듈의 컴파일된 표로 모든 키를, `LauncherTextSyncTests` 는 Launcher 원본 표로 공유 키를 본다.
enum AppLogTextCatalog {
  typealias Check = DownloadTextCatalog.Check

  /// iOS 기기 목록(Launcher)의 `LauncherText.viewLog*`·`launchAppSheetNote` 와 같은 키·값으로 둔 문구.
  static func sharedChecks(_ table: [String: String]) -> [Check] {
    let pairs: [(String, String)] = [
      ("로그 보기", AndroidDevicesText.viewLogButton),
      ("이 기기에서 실행한 앱의 로그 창을 엽니다", AndroidDevicesText.viewLogHelp),
      (
        "앱 실행… 이나 앱 설치로 SimLauncher 가 이 기기에서 앱을 실행하면 로그를 볼 수 있습니다",
        AndroidDevicesText.viewLogUnavailableHelp
      ),
      (
        "이미 실행 중이면 끝내고 다시 실행합니다. 실행한 뒤 로그 보기로 앱 로그를 볼 수 있습니다.",
        AndroidDevicesText.launchAppSheetNote
      ),
    ]
    return pairs.map { DownloadTextCatalog.check(table, $0.0, $0.1) }
  }

  /// Android 문장 (iOS 는 기기를 켜는 문장이 더 붙어 공유하지 않는다).
  static func androidChecks(_ table: [String: String]) -> [Check] {
    [DownloadTextCatalog.check(table, "이 기기에 설치한 앱 중 하나를 골라 로그를 받으며 실행합니다.", AndroidDevicesText.launchAppHelp)]
  }
}
