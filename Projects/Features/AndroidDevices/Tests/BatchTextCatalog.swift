import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
@testable import AndroidDevicesFeature

/// 여러 기기 설치 문구(`AndroidDevicesText+Batch.swift`, `.deviceBusy` 본문)의 String Catalog 키. `DownloadTextCatalog` 와 같은
/// 방식으로 `AndroidDevicesResourcesTests` 는 이 모듈의 컴파일된 표로 모든 키를, `LauncherTextSyncTests` 는 Launcher 원본 표로 공유
/// 키를 본다.
enum BatchTextCatalog {
  typealias Check = DownloadTextCatalog.Check

  static let tablet = AndroidDeviceLabel(.bootedTabletSample)
  static let phone = AndroidDeviceLabel(.phoneSample)
  static let targets = [AndroidVirtualDevice.bootedTabletSample, .phoneSample].map(AndroidTargetDevice.init)

  /// iOS 기기 목록(Launcher)의 `LauncherText+Batch`·`.deviceBusy` 와 같은 키·값으로 둔 문구.
  static func sharedChecks(_ table: [String: String]) -> [Check] {
    self.menuChecks(table) + self.resultChecks(table)
  }

  /// 툴바·시트·행 문구.
  private static func menuChecks(_ table: [String: String]) -> [Check] {
    let names = AndroidDevicesText.deviceNames([self.tablet, self.phone])
    return [
      DownloadTextCatalog.check(table, "선택한 기기에 앱 설치", AndroidDevicesText.installOnSelectionMenu),
      DownloadTextCatalog.check(
        table,
        "고른 기기 %lld대에 앱을 설치하고 실행합니다. 설치할 수 없는 기기는 이유와 함께 건너뜁니다.",
        AndroidDevicesText.installOnSelectionHelp(count: 3),
        3
      ),
      DownloadTextCatalog.check(
        table,
        "기기 %lld대에 URL 에서 앱 설치",
        AndroidDevicesText.installURLSheetTitle(for: self.targets),
        2
      ),
      DownloadTextCatalog.check(
        table,
        "기기 %lld대에 카탈로그에서 앱 설치",
        AndroidDevicesText.catalogSheetTitle(for: self.targets),
        2
      ),
      DownloadTextCatalog.check(table, "대상: %@", AndroidDevicesText.batchTargetsLine(self.targets) ?? "", names),
      DownloadTextCatalog.check(
        table,
        "기기 %lld대에 함께 받는 중입니다. 취소하면 모두 멈추고 받은 부분을 지웁니다.",
        AndroidDevicesText.batchCancelDownloadHelp(count: 2),
        2
      ),
    ]
  }

  /// 결과 알림 문구와 `.deviceBusy` 본문.
  private static func resultChecks(_ table: [String: String]) -> [Check] {
    let tabletName = AndroidDevicesText.label(self.tablet)
    let busy = "이 기기에서 다른 작업이 진행 중이라 설치하지 않았습니다. 끝난 뒤 이 기기에만 다시 설치하세요."
    let notReady = AndroidDevicesText.message(for: AndroidAppInstallFailure.deviceNotReady(.notBooted))
    let noLauncher = AndroidDevicesText.installedButNotLaunchedMessage(for: .launchFailed(.noLauncherActivity))
    let mixed = AndroidBatchInstallReport(entries: [
      .init(device: self.tablet, result: .succeeded),
      .init(device: self.phone, result: .installFailed(.deviceNotReady(.notBooted))),
    ])
    let failed = AndroidBatchInstallReport(entries: [.init(device: self.phone, result: .installFailed(.deviceBusy))])
    let launch = AndroidBatchInstallReport(entries: [
      .init(device: self.tablet, result: .launchFailed(.launchFailed(.noLauncherActivity))),
    ])
    let mixedLines = AndroidDevicesText.batchInstallMessage(for: mixed).components(separatedBy: "\n\n")
    return [
      DownloadTextCatalog.check(
        table,
        "기기 %lld대 중 %lld대에 앱을 설치했습니다",
        AndroidDevicesText.title(for: .batchInstallFinished(mixed)),
        2,
        1
      ),
      DownloadTextCatalog.check(
        table,
        "기기 %lld대에 앱을 설치하지 못했습니다",
        AndroidDevicesText.title(for: .batchInstallFinished(failed)),
        1
      ),
      DownloadTextCatalog.check(table, "%@: 설치하고 실행했습니다.", mixedLines.first ?? "", tabletName),
      DownloadTextCatalog.check(
        table,
        "%@: 설치하지 못했습니다. %@",
        mixedLines.last ?? "",
        AndroidDevicesText.label(self.phone),
        notReady
      ),
      DownloadTextCatalog.check(
        table,
        "%@: 설치했지만 실행하지 못했습니다. %@",
        AndroidDevicesText.batchInstallMessage(for: launch),
        tabletName,
        noLauncher
      ),
      DownloadTextCatalog.check(table, busy, AndroidDevicesText.message(for: AndroidAppInstallFailure.deviceBusy)),
    ]
  }

  /// Android 만의 문장 (꺼진 기기를 켜고 설치하지 않아 iOS 와 이유가 다르다).
  static func androidChecks(_ table: [String: String]) -> [Check] {
    [
      DownloadTextCatalog.check(
        table,
        "고른 기기 중 앱을 설치할 수 있는 기기가 없습니다. 켜져 있지 않거나, 사용할 수 없거나, 다른 작업 중입니다.",
        AndroidDevicesText.installOnSelectionUnavailable
      ),
    ]
  }
}
