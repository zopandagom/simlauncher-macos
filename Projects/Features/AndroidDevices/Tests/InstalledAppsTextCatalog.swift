import AndroidEmulatorInterface
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 설치된 앱 문구(`AndroidDevicesText+InstalledApps.swift`)의 String Catalog 키. `DownloadTextCatalog` 와 같은 방식으로
/// `AndroidDevicesResourcesTests` 는 이 모듈의 컴파일된 표로 모든 키를, `LauncherTextSyncTests` 는 Launcher 원본 표로 공유 키를 본다.
enum InstalledAppsTextCatalog {
  typealias Check = DownloadTextCatalog.Check

  static let device = AndroidDeviceLabel(name: "Pixel Tablet", apiLabel: "37.0")
  static let package = AndroidPackageName("com.example.sample")!

  /// iOS 기기 목록(Launcher)의 `LauncherText+InstalledApps.swift` 와 같은 키·값으로 둔 문구 ("(공통)").
  static func sharedChecks(_ table: [String: String]) -> [Check] {
    let pairs: [(String, String)] = [
      ("설치된 앱…", AndroidDevicesText.installedAppsButton),
      ("이 기기에 설치한 앱을 보고 지웁니다.", AndroidDevicesText.installedAppsHelp),
      (
        "켜진 기기에서만 설치된 앱을 볼 수 있습니다. 기기를 켠 뒤 다시 시도하세요",
        AndroidDevicesText.installedAppsBlockReason(.notBooted)
      ),
      ("사용할 수 없는 기기에서는 설치된 앱을 볼 수 없습니다", AndroidDevicesText.installedAppsBlockReason(.unavailable)),
      ("직접 설치한 앱만 보입니다. 지운 앱은 다시 설치해야 합니다.", AndroidDevicesText.installedAppsSheetNote),
      ("삭제…", AndroidDevicesText.removeAppButton),
      ("삭제", AndroidDevicesText.removeAppConfirmButton),
    ]
    let name = self.package.rawValue
    return pairs.map { DownloadTextCatalog.check(table, $0.0, $0.1) } + [
      DownloadTextCatalog.check(
        table, "%@ 설치된 앱", AndroidDevicesText.installedAppsSheetTitle(for: self.device), "Pixel Tablet"
      ),
      DownloadTextCatalog.check(table, "%@ 앱을 지우는 중…", AndroidDevicesText.removingApp(name), name),
      DownloadTextCatalog.check(table, "%@ 앱을 지울까요?", AndroidDevicesText.removeAppConfirmationTitle(name), name),
      DownloadTextCatalog.check(
        table, "%@ 앱을 지웠습니다.", AndroidDevicesText.installedAppsMessage(.removed(self.package)), name
      ),
      DownloadTextCatalog.check(
        table,
        "%@ 앱을 지우지 못했습니다. %@",
        AndroidDevicesText.installedAppsMessage(.failed(.remove(self.package), .deviceNotBooted)),
        name,
        AndroidDevicesText.testConditionsFailure(.deviceNotBooted)
      ),
    ]
  }

  /// Android 문장 (iOS 는 번들 ID 와 런타임 이름을 보여 문장이 다르다).
  static func androidChecks(_ table: [String: String]) -> [Check] {
    [
      DownloadTextCatalog.check(
        table,
        "%@ 기기에서 앱과 앱 데이터를 지웁니다. 실행 중이면 종료됩니다. 되돌릴 수 없습니다.",
        AndroidDevicesText.removeAppConfirmationMessage(on: self.device),
        AndroidDevicesText.label(self.device)
      ),
    ]
  }
}

/// 설치된 앱 문구 함수가 각 경우에 돌려주는 값.
struct AndroidInstalledAppsTextTests {
  @Test("실패 결과 줄의 이유는 테스트 조건 시트와 같은 문구다")
  func failureReasons() {
    let package = InstalledAppsTextCatalog.package
    for error in [AndroidEmulatorError.deviceNotBooted, .deviceNotFound, .adbUnavailable, .appCommandFailed] {
      #expect(
        AndroidDevicesText.installedAppsMessage(.failed(.remove(package), error))
          == AndroidDevicesText.removeAppFailed(
            package.rawValue,
            reason: AndroidDevicesText.testConditionsFailure(error)
          ),
        "\(error)"
      )
    }
    #expect(
      AndroidDevicesText.removeAppConfirmationMessage(on: InstalledAppsTextCatalog.device)
        == "“Pixel Tablet” (API 37.0) 기기에서 앱과 앱 데이터를 지웁니다. 실행 중이면 종료됩니다. 되돌릴 수 없습니다."
    )
  }

  @Test("공유 문구 12개와 Android 문구 1개")
  func checkCounts() {
    #expect(Set(InstalledAppsTextCatalog.sharedChecks([:]).map(\.key)).count == 12)
    #expect(Set(InstalledAppsTextCatalog.androidChecks([:]).map(\.key)).count == 1)
  }
}
