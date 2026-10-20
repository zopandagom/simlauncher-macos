import Core
import DevEnvironmentInterface
import Foundation

/// 화면 문구. 모두 이 모듈의 `Localizable.xcstrings` 에서 찾는다 (`bundle: .module`).
/// Xcode 버전·경로는 여기를 거치지 않고 그대로(`Text(verbatim:)`) 보인다.
/// 케이스를 기본값 없이 모두 적어, 상태·오류가 늘면 컴파일러가 잡는다.
enum SetupText {
  // MARK: - 상태별 안내

  static let checkingTitle = String(localized: "개발 환경을 확인하는 중…", bundle: .module)

  static func title(for status: DevEnvironmentStatus) -> String {
    switch status {
    case .xcodeNotInstalled, .commandLineToolsOnly:
      String(localized: "Xcode 를 설치하세요", bundle: .module)
    case .licenseNotAccepted:
      String(localized: "Xcode 라이선스에 동의하세요", bundle: .module)
    case .firstLaunchRequired:
      String(localized: "Xcode 첫 실행 준비를 마치세요", bundle: .module)
    case .ready:
      String(localized: "준비가 끝났습니다", bundle: .module)
    }
  }

  static func message(for status: DevEnvironmentStatus) -> String {
    switch status {
    case .xcodeNotInstalled:
      String(
        localized: "iOS 시뮬레이터를 쓰려면 Xcode 가 필요합니다. App Store 열기를 눌러 Xcode 를 설치하세요. 내려받는 데 시간이 걸릴 수 있습니다.",
        bundle: .module
      )
    case .commandLineToolsOnly:
      String(
        localized: """
        이 Mac 에는 Command Line Tools 만 설치되어 있습니다. Command Line Tools 로는 iOS 시뮬레이터를 쓸 수 없어 \
        Xcode 가 필요합니다. App Store 열기를 눌러 Xcode 를 설치하세요.
        """,
        bundle: .module
      )
    case .licenseNotAccepted:
      String(localized: "Xcode 열기를 누르면 Xcode 가 라이선스 동의 창을 띄웁니다. 창의 안내에 따라 동의하세요.", bundle: .module)
    case .firstLaunchRequired:
      String(
        localized: "Xcode 열기를 누르면 Xcode 가 추가 구성요소를 설치하는 창을 띄웁니다. 창의 안내에 따라 설치하고 끝날 때까지 기다리세요.",
        bundle: .module
      )
    case .ready:
      String(localized: "이제 iOS 시뮬레이터 기기를 켜고 앱을 설치할 수 있습니다.", bundle: .module)
    }
  }

  // MARK: - 확인 실패

  static let failedTitle = String(localized: "Xcode 상태를 확인하지 못했습니다", bundle: .module)

  static func message(for error: DevEnvironmentError) -> String {
    switch error {
    case .checkFailed:
      String(
        localized: "Xcode 를 설치하거나 업데이트하는 중이면 끝난 뒤 다시 확인을 누르세요. 계속 실패하면 App Store 에서 Xcode 를 다시 설치하세요.",
        bundle: .module
      )
    case .xcodeNotFound:
      String(localized: "Xcode 를 찾지 못했습니다. App Store 에서 Xcode 를 설치한 뒤 다시 확인을 누르세요.", bundle: .module)
    case .openFailed:
      String(localized: "다시 확인을 누르세요. 계속 실패하면 Mac 을 재시동한 뒤 다시 시도하세요.", bundle: .module)
    }
  }

  // MARK: - 단계

  static func stepTitle(_ kind: SetupStep.Kind) -> String {
    switch kind {
    case .installXcode:
      String(localized: "Xcode 설치", bundle: .module)
    case .acceptLicense:
      String(localized: "라이선스 동의", bundle: .module)
    case .firstLaunch:
      String(localized: "첫 실행 준비", bundle: .module)
    }
  }

  static let adminPasswordNote = String(localized: "관리자 암호가 필요합니다", bundle: .module)
  static let autoRecheckNote = String(localized: "단계를 마치고 이 앱으로 돌아오면 자동으로 다시 확인합니다.", bundle: .module)
  static let currentXcodeLabel = String(localized: "사용하는 Xcode", bundle: .module)

  /// 화면에 보일 번들 경로. 디렉터리 URL 의 끝 `/` 를 뗀다 (`/Applications/Xcode.app/` → `/Applications/Xcode.app`).
  static func xcodeLocation(_ bundleURL: URL) -> String {
    let path = bundleURL.path(percentEncoded: false)
    guard path.count > 1, path.hasSuffix("/") else { return path }
    return String(path.dropLast())
  }

  // MARK: - 버튼·진행

  static let openAppStoreButton = String(localized: "App Store 열기", bundle: .module)
  static let openXcodeButton = String(localized: "Xcode 열기", bundle: .module)
  static let recheckButton = String(localized: "다시 확인", bundle: .module)
  static let finishButton = String(localized: "기기 목록 열기", bundle: .module)
  static let okButton = String(localized: "확인", bundle: .module)
  static let recheckingLabel = String(localized: "확인 중…", bundle: .module)

  // MARK: - 알림

  /// 알림 제목. 알림이 없으면 빈 문자열 (알림을 띄우기 전, 표시되지 않는 `.alert` 가 읽는다).
  static func title(for notice: SetupNotice?) -> String {
    switch notice {
    case .none:
      ""
    case .openAppStoreFailed:
      String(localized: "App Store 를 열지 못했습니다", bundle: .module)
    case .openXcodeFailed(.xcodeNotFound):
      String(localized: "Xcode 를 찾지 못했습니다", bundle: .module)
    case .openXcodeFailed(.openFailed), .openXcodeFailed(.checkFailed):
      String(localized: "Xcode 를 열지 못했습니다", bundle: .module)
    }
  }

  /// 알림 본문: 직접 할 수 있는 다음 일.
  static func message(for notice: SetupNotice) -> String {
    switch notice {
    case .openAppStoreFailed:
      String(localized: "App Store 앱을 직접 열고 Xcode 를 검색해 설치하세요.", bundle: .module)
    case .openXcodeFailed(.xcodeNotFound):
      String(localized: "Xcode 가 삭제되었거나 옮겨졌습니다. 화면의 안내에 따라 Xcode 를 다시 설치하세요.", bundle: .module)
    case .openXcodeFailed(.openFailed), .openXcodeFailed(.checkFailed):
      String(localized: "Finder 의 응용 프로그램 폴더에서 Xcode 를 직접 열어 주세요.", bundle: .module)
    }
  }
}
