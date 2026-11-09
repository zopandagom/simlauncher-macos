import Core
import Foundation
import SimulatorInterface

/// 설치된 앱 실행("앱 실행…") 문구. 키는 다른 문구와 같은 `Localizable.xcstrings` 에 있다.
extension LauncherText {
  // MARK: - 기기 행

  static var launchAppButton: String {
    String(localized: "앱 실행…", bundle: .module)
  }

  static var launchAppHelp: String {
    String(
      localized: "이 기기에 설치한 앱 중 하나를 골라 로그를 받으며 실행합니다. 기기가 꺼져 있으면 켭니다.",
      bundle: .module
    )
  }

  static var launchingAppLabel: String {
    String(localized: "앱을 실행하는 중…", bundle: .module)
  }

  /// 앱 실행 버튼이 막힌 이유. 시트를 연 사이 기기 상태가 바뀐 실패의 본문에도 쓴다.
  /// 막힘 규칙은 앱 설치와 같다 (`appInstallAvailability`).
  static func launchAppBlockReason(_ reason: AppInstallBlockReason) -> String {
    switch reason {
    case .unavailable:
      String(localized: "사용할 수 없는 기기에서는 앱을 실행할 수 없습니다", bundle: .module)
    case .stateChanging:
      String(localized: "기기를 켜거나 끄는 중에는 앱을 실행할 수 없습니다. 끝난 뒤 다시 시도하세요", bundle: .module)
    }
  }

  // MARK: - 시트

  static func launchAppSheetTitle(for device: LauncherNotice.Device) -> String {
    String(localized: "“\(device.name)” (\(device.runtimeName)) 기기에서 앱 실행", bundle: .module)
  }

  static var loadingInstalledApps: String {
    String(localized: "설치한 앱 목록을 불러오는 중…", bundle: .module)
  }

  static var bootingForAppList: String {
    String(localized: "기기를 켜는 중… 켜지면 설치한 앱 목록을 불러옵니다.", bundle: .module)
  }

  static var noInstalledApps: String {
    String(localized: "이 기기에 직접 설치한 앱이 없습니다. 앱 설치로 먼저 설치하세요.", bundle: .module)
  }

  /// 앱 목록의 접근성 이름.
  static var installedAppPicker: String {
    String(localized: "앱", bundle: .module)
  }

  /// 목록 행의 버전 글자. 앱이 정한 값이라 그대로 넣는다. 둘 다 없으면 nil.
  static func appVersionLabel(version: String?, build: String?) -> String? {
    switch (version, build) {
    case let (version?, build?):
      String(localized: "버전 \(version) (\(build))", bundle: .module)
    case let (version?, nil):
      String(localized: "버전 \(version)", bundle: .module)
    case let (nil, build?):
      String(localized: "빌드 \(build)", bundle: .module)
    case (nil, nil):
      nil
    }
  }

  static var launchAppSheetNote: String {
    String(
      localized: "이미 실행 중이면 끝내고 다시 실행합니다. 실행한 뒤 로그 보기로 앱 로그를 볼 수 있습니다.",
      bundle: .module
    )
  }

  static var launchAppConfirmButton: String {
    String(localized: "실행", bundle: .module)
  }

  static var closeButton: String {
    String(localized: "닫기", bundle: .module)
  }

  /// 시트의 실패 본문 위 한 줄 제목: 켜기 실패와 목록 읽기 실패를 가른다.
  static func launchAppFailureHeading(for stage: LaunchAppFailureStage) -> String {
    switch stage {
    case .boot:
      String(localized: "기기를 켜지 못했습니다", bundle: .module)
    case .list:
      String(localized: "앱 목록을 읽지 못했습니다", bundle: .module)
    }
  }

  /// 시트의 실패 본문. 꺼져 있어 읽지 못했으면 "다시 시도" 가 켜고 읽는다고 안내하고, 켜기 실패는 기존 켜기 실패 본문과 같다.
  static func launchAppListMessage(for failure: InstalledAppLaunchFailure) -> String {
    switch failure {
    case .simulator(.deviceNotBooted):
      String(
        localized: "기기가 꺼져 있어 앱 목록을 읽지 못했습니다. 다시 시도를 누르면 기기를 켜고 읽습니다.",
        bundle: .module
      )
    case let .deviceNotReady(reason):
      self.launchAppBlockReason(reason)
    case let .simulator(error):
      self.message(for: error)
    }
  }

  // MARK: - 알림

  static func installedAppLaunchNoticeTitle(for device: LauncherNotice.Device) -> String {
    String(localized: "“\(device.name)” (\(device.runtimeName)) 기기에서 앱을 실행하지 못했습니다", bundle: .module)
  }

  static func message(for failure: InstalledAppLaunchFailure) -> String {
    switch failure {
    case let .deviceNotReady(reason):
      self.launchAppBlockReason(reason)
    case let .simulator(error):
      self.message(for: error)
    }
  }
}
