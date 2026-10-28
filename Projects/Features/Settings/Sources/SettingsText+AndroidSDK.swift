import Core
import Foundation

/// "Android SDK 위치" 절의 문구. 키는 다른 문구와 같은 `Localizable.xcstrings` 에 있다. 경로는 번역하지 않고 그대로 보인다.
extension SettingsText {
  static var androidSDKSectionTitle: String {
    String(localized: "Android SDK 위치", bundle: .module)
  }

  static var androidSDKDefaultBadge: String {
    String(localized: "기본 위치", bundle: .module)
  }

  static var androidSDKChooseButton: String {
    String(localized: "다른 폴더 고르기…", bundle: .module)
  }

  static var androidSDKResetButton: String {
    String(localized: "기본 위치로 되돌리기", bundle: .module)
  }

  static var androidSDKInspecting: String {
    String(localized: "폴더를 확인하는 중…", bundle: .module)
  }

  static var androidSDKLockedNote: String {
    String(
      localized: "관리자가 정한 위치라 이 Mac 에서 바꿀 수 없습니다. 바꾸려면 Mac 을 관리하는 담당자에게 문의하세요.",
      bundle: .module
    )
  }

  /// 저장 값을 경로로 읽을 수 없다. 잠겼으면 바꿀 수 없으니 담당자 문의만 안내한다.
  static func androidSDKInvalidSetting(isLocked: Bool) -> String {
    if isLocked {
      String(localized: "설정된 SDK 위치를 읽을 수 없습니다. Mac 을 관리하는 담당자에게 문의하세요.", bundle: .module)
    } else {
      String(localized: "설정된 SDK 위치를 읽을 수 없습니다. 다른 폴더를 고르거나 기본 위치로 되돌리세요.", bundle: .module)
    }
  }

  static var androidSDKGuide: String {
    String(
      localized: "빈 폴더나 Android SDK 가 든 폴더를 고르세요. 빈 폴더면 Android 화면에서 설치할 때 그곳에 설치하고, SDK 폴더면 있는 도구를 덮어쓰지 않고 그대로 씁니다.",
      bundle: .module
    )
  }

  /// 설정 창은 설치 상태를 모르므로 늘 보인다.
  static var androidSDKInstallNote: String {
    String(localized: "진행 중인 설치는 원래 위치에 끝까지 설치합니다.", bundle: .module)
  }

  // MARK: - 고른 폴더의 판정

  /// 고른 폴더의 판정 결과 줄. 저장했으면 그 위치가 어떻게 쓰이는지, 저장하지 않았으면 이유와 다음 할 일.
  static func sdkFolderResult(_ result: SettingsSDKFolderResult) -> String {
    switch result.candidate {
    case .empty where result.writable:
      String(localized: "비어 있는 폴더입니다. Android 화면에서 설치하면 이곳에 설치합니다.", bundle: .module)
    case .empty:
      String(
        localized: "이 폴더에 쓸 수 없어 저장하지 않았습니다. 쓸 수 있는 빈 폴더나 SDK 폴더를 고르세요.",
        bundle: .module
      )
    case .sdk where result.writable:
      String(localized: "SDK 폴더입니다. 있는 도구는 그대로 씁니다.", bundle: .module)
    case .sdk:
      String(
        localized: "SDK 폴더입니다. 있는 도구는 그대로 쓰지만, 이 위치에 쓸 수 없어 없는 도구를 설치할 수 없습니다.",
        bundle: .module
      )
    case .otherContents:
      String(
        localized: "SDK 가 아닌 파일이 들어 있어 저장하지 않았습니다. 빈 폴더나 SDK 폴더를 고르세요.",
        bundle: .module
      )
    case .notDirectory:
      String(localized: "폴더가 아니어서 저장하지 않았습니다. 폴더를 고르세요.", bundle: .module)
    case .missing:
      String(localized: "고른 폴더를 찾을 수 없어 저장하지 않았습니다. 다시 고르세요.", bundle: .module)
    case .unreadable:
      String(localized: "폴더를 읽을 수 없어(권한) 저장하지 않았습니다. 다른 폴더를 고르세요.", bundle: .module)
    case .unsupportedVolume:
      String(
        localized: "이 디스크 형식(exFAT 등)에는 설치할 수 없어 저장하지 않았습니다. APFS 나 Mac OS 확장 디스크의 폴더를 고르세요.",
        bundle: .module
      )
    }
  }
}
