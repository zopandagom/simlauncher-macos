import Foundation
import SimulatorInterface

/// `SimulatorError` 본문의 분류별 문구 (`message(for:)` 가 고른다). 앱 설치·실행 분류는 `LauncherText+Install.swift`,
/// 링크 열기 분류는 `LauncherText+OpenURL.swift`.
extension LauncherText {
  /// Xcode·개발 도구 준비 문제. 다른 분류면 nil.
  static func setupMessage(for error: SimulatorError) -> String? {
    switch error {
    case .developerToolsUnavailable:
      String(
        localized: "Xcode 를 찾지 못했거나 아직 준비되지 않았습니다. Xcode 를 설치하고 한 번 실행해 준비를 마친 뒤 다시 시도하세요.",
        bundle: .module
      )
    case .simulatorAppNotFound:
      String(
        localized: "이 Mac 의 Xcode 에서 Simulator 앱을 찾지 못했습니다. Xcode 를 최신 버전으로 업데이트하거나 다시 설치하세요.",
        bundle: .module
      )
    case .unexpectedOutput:
      String(
        localized: "Xcode 가 알려 준 기기 정보를 읽지 못했습니다. Xcode 를 최신 버전으로 업데이트한 뒤 다시 시도하세요.",
        bundle: .module
      )
    case .commandFailed:
      self.commandFailedMessage
    case .deviceNotFound, .deviceNotShutdown, .creationOptionUnavailable, .invalidDeviceName, .creationResultUnknown,
         .deviceNotBooted, .appNotFound, .appInvalid, .appIncompatible, .appRequiresNewerOS, .appNotInstalled,
         .appLaunchFailed, .urlNotHandled, .invalidURL:
      nil
    }
  }

  /// 기기 만들기·삭제·초기화 문제. 다른 분류면 nil.
  static func deviceMessage(for error: SimulatorError) -> String? {
    switch error {
    case .deviceNotFound:
      String(localized: "이 기기를 더 이상 찾을 수 없습니다. 목록을 새로 고친 뒤 다른 기기를 골라 주세요.", bundle: .module)
    case .deviceNotShutdown:
      String(
        localized: "켜져 있거나 상태가 바뀌는 중인 기기는 삭제하거나 초기화할 수 없습니다. 기기를 끈 뒤 다시 시도하세요.",
        bundle: .module
      )
    case .creationOptionUnavailable:
      String(
        localized: "고른 iOS 버전이나 기기 종류를 지금 사용할 수 없습니다. 목록을 새로 고친 뒤 다시 골라 주세요.",
        bundle: .module
      )
    case .invalidDeviceName:
      String(localized: "기기 이름은 1~100자로, 줄바꿈 같은 제어 문자 없이 입력하세요.", bundle: .module)
    case .creationResultUnknown:
      // simctl create 는 성공했지만 출력에서 UDID 를 읽지 못해 기기가 생겼을 수 있다.
      // 다시 만들면 같은 이름 기기가 하나 더 생기므로 목록부터 확인하게 한다.
      String(
        localized: """
        Xcode 가 알려 준 결과를 읽지 못해 기기가 만들어졌는지 확인하지 못했습니다. \
        기기가 만들어졌을 수 있으니 목록을 확인한 뒤, 없을 때만 다시 만드세요.
        """,
        bundle: .module
      )
    case .developerToolsUnavailable, .simulatorAppNotFound, .unexpectedOutput, .commandFailed, .deviceNotBooted,
         .appNotFound, .appInvalid, .appIncompatible, .appRequiresNewerOS, .appNotInstalled, .appLaunchFailed,
         .urlNotHandled, .invalidURL:
      nil
    }
  }

  /// 그 밖의 실패.
  static var commandFailedMessage: String {
    String(
      localized: "Xcode 를 한 번 실행해 라이선스 동의와 준비를 마쳤는지 확인한 뒤 다시 시도하세요. 계속 실패하면 Mac 을 재시동한 뒤 다시 시도하세요.",
      bundle: .module
    )
  }
}
