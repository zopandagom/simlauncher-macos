import Core
import Foundation
import SimulatorInterface

/// 링크 열기 문구. 키는 다른 문구와 같은 `Localizable.xcstrings` 에 있다.
extension LauncherText {
  // MARK: - 기기 행

  static var openURLButton: String {
    String(localized: "링크 열기…", bundle: .module)
  }

  static var openURLHelp: String {
    String(
      localized: "앱 스킴 링크(딥링크)나 웹 주소를 입력해 이 기기에서 엽니다. 기기가 꺼져 있으면 켭니다.",
      bundle: .module
    )
  }

  static var openingURLLabel: String {
    String(localized: "링크를 여는 중…", bundle: .module)
  }

  /// 링크 열기 버튼이 막힌 이유. 시트를 연 사이 기기 상태가 바뀐 실패의 본문에도 쓴다.
  /// 막힘 규칙은 앱 설치와 같다 (`appInstallAvailability`).
  static func openURLBlockReason(_ reason: AppInstallBlockReason) -> String {
    switch reason {
    case .unavailable:
      String(localized: "사용할 수 없는 기기에서는 링크를 열 수 없습니다", bundle: .module)
    case .stateChanging:
      String(localized: "기기를 켜거나 끄는 중에는 링크를 열 수 없습니다. 끝난 뒤 다시 시도하세요", bundle: .module)
    }
  }

  // MARK: - 시트

  static func openURLSheetTitle(for device: LauncherNotice.Device) -> String {
    String(localized: "“\(device.name)” (\(device.runtimeName)) 기기에서 링크 열기", bundle: .module)
  }

  static var linkField: String {
    String(localized: "링크", bundle: .module)
  }

  static var linkPrompt: String {
    String(localized: "예: myapp://item/1 또는 https://example.com", bundle: .module)
  }

  static var openURLConfirmButton: String {
    String(localized: "열기", bundle: .module)
  }

  /// 입력란 아래 안내. 비어 있으면 문구 없이 열기 버튼만 비활성이다 (nil).
  static func linkProblem(_ problem: DeepLinkProblem) -> String? {
    switch problem {
    case .empty:
      nil
    case .malformed:
      String(
        localized: """
        링크로 읽을 수 없습니다. 앞에 myapp:// 나 https:// 같은 스킴이 있는지, \
        스킴과 호스트(:// 앞뒤)에 공백이나 쓸 수 없는 문자가 없는지 확인하세요.
        """,
        bundle: .module
      )
    case .missingScheme:
      String(localized: "링크 앞에 myapp:// 나 https:// 같은 스킴을 붙여 입력하세요.", bundle: .module)
    }
  }

  // MARK: - 알림

  static func openURLNoticeTitle(for device: LauncherNotice.Device) -> String {
    String(localized: "“\(device.name)” (\(device.runtimeName)) 기기에서 링크를 열지 못했습니다", bundle: .module)
  }

  static func message(for failure: OpenURLFailure) -> String {
    switch failure {
    case let .deviceNotReady(reason):
      self.openURLBlockReason(reason)
    case let .simulator(error):
      self.message(for: error)
    }
  }

  /// 링크 열기 명령의 실패. 다른 분류면 nil.
  static func linkMessage(for error: SimulatorError) -> String? {
    switch error {
    case .urlNotHandled:
      String(
        localized: """
        이 링크를 열 수 있는 앱이 기기에 없습니다. \
        링크를 처리할 앱을 이 기기에 먼저 설치했는지, 링크의 스킴(:// 앞부분) 철자가 맞는지 확인하세요.
        """,
        bundle: .module
      )
    case .invalidURL:
      String(localized: "기기가 이 링크의 형식을 받아들이지 않았습니다. 링크를 다시 확인해 입력하세요.", bundle: .module)
    case .developerToolsUnavailable, .deviceNotFound, .deviceNotShutdown, .creationOptionUnavailable,
         .invalidDeviceName, .simulatorAppNotFound, .unexpectedOutput, .creationResultUnknown, .commandFailed,
         .deviceNotBooted, .appNotFound, .appInvalid, .appIncompatible, .appRequiresNewerOS, .appNotInstalled,
         .appLaunchFailed, .recordingInProgress, .recordingEmpty, .recordingUnfinished:
      nil
    }
  }
}
