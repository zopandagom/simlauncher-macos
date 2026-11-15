import Core
import Foundation
import SimulatorInterface
import Testing
@testable import LauncherFeature

/// 설치된 앱 문구(`LauncherText+InstalledApps.swift`)의 String Catalog 키. `LauncherResourcesTests` 가 컴파일된 표로 모든 키를
/// 본다. "(공통)" 키는 Android 기기 목록의 `LauncherTextSyncTests` 가 Launcher 원본 카탈로그로 다시 본다.
enum InstalledAppsTextCatalog {
  typealias Check = CatalogTextCatalog.Check

  static let device = LauncherNotice.Device(name: "iPhone 17", runtimeName: "iOS 26.0")
  static let app = InstalledApp(
    bundleID: AppBundleID("com.example.sample")!,
    displayName: "Sample",
    version: nil,
    build: nil
  )

  static func checks(_ table: [String: String]) -> [Check] {
    let pairs: [(String, String)] = [
      ("설치된 앱…", LauncherText.installedAppsButton),
      ("이 기기에 설치한 앱을 보고 지웁니다.", LauncherText.installedAppsHelp),
      ("켜진 기기에서만 설치된 앱을 볼 수 있습니다. 기기를 켠 뒤 다시 시도하세요", LauncherText.installedAppsBlockReason(.notBooted)),
      ("사용할 수 없는 기기에서는 설치된 앱을 볼 수 없습니다", LauncherText.installedAppsBlockReason(.unavailable)),
      ("직접 설치한 앱만 보입니다. 지운 앱은 다시 설치해야 합니다.", LauncherText.installedAppsSheetNote),
      ("삭제…", LauncherText.removeAppButton),
      ("삭제", LauncherText.removeAppConfirmButton),
    ]
    return pairs.map { CatalogTextCatalog.check(table, $0.0, $0.1) } + [
      CatalogTextCatalog.check(table, "%@ 설치된 앱", LauncherText.installedAppsSheetTitle(for: self.device), "iPhone 17"),
      CatalogTextCatalog.check(table, "%@ 앱을 지우는 중…", LauncherText.removingApp("Sample"), "Sample"),
      CatalogTextCatalog.check(table, "%@ 앱을 지울까요?", LauncherText.removeAppConfirmationTitle("Sample"), "Sample"),
      CatalogTextCatalog.check(
        table,
        "번들 ID: %@\n“%@” (%@) 기기에서 앱과 앱 데이터를 지웁니다. 실행 중이면 종료됩니다. 되돌릴 수 없습니다.",
        LauncherText.removeAppConfirmationMessage(self.app, on: self.device),
        "com.example.sample",
        "iPhone 17",
        "iOS 26.0"
      ),
      CatalogTextCatalog.check(
        table, "%@ 앱을 지웠습니다.", LauncherText.installedAppsMessage(.removed(appName: "Sample")), "Sample"
      ),
      CatalogTextCatalog.check(
        table,
        "%@ 앱을 지우지 못했습니다. %@",
        LauncherText.installedAppsMessage(.failed(.remove(self.app), .commandFailed)),
        "Sample",
        LauncherText.commandFailedMessage
      ),
    ]
  }

  /// 표에 키가 있고 값이 키와 같으며 코드 결과가 표의 값과 같은지 보고, 키를 돌려준다.
  static func checkedKeys(in table: [String: String]) -> Set<String> {
    let checks = self.checks(table)
    for check in checks {
      #expect(table[check.key] == check.key, "\(check.key)")
      #expect(check.actual == check.expected, "\(check.key)")
    }
    let keys = Set(checks.map(\.key))
    #expect(keys.count == 13)
    return keys
  }
}

/// 설치된 앱 문구 함수가 각 경우에 돌려주는 값.
struct InstalledAppsTextTests {
  @Test("실패 결과 줄의 이유는 테스트 조건 시트와 같은 문구다 (꺼짐·없어짐은 시트 문구, 그 밖은 오류 분류 문구)")
  func failureReasons() {
    let app = InstalledAppsTextCatalog.app
    for error in [SimulatorError.deviceNotBooted, .deviceNotFound, .commandFailed, .developerToolsUnavailable] {
      #expect(
        LauncherText.installedAppsMessage(.failed(.remove(app), error))
          == LauncherText.removeAppFailed("Sample", reason: LauncherText.testConditionsFailure(error)),
        "\(error)"
      )
    }
    #expect(
      LauncherText.installedAppsMessage(.failed(.remove(app), .deviceNotBooted))
        == "Sample 앱을 지우지 못했습니다. 기기가 꺼져 있습니다. 기기를 켠 뒤 다시 시도하세요."
    )
  }

  @Test("확인 본문은 번들 ID 와 기기 이름·런타임을 보인다")
  func confirmationMessageNamesAppAndDevice() {
    let message = LauncherText.removeAppConfirmationMessage(
      InstalledAppsTextCatalog.app,
      on: InstalledAppsTextCatalog.device
    )
    #expect(message.contains("com.example.sample"))
    #expect(message.contains("“iPhone 17” (iOS 26.0)"))
  }
}
