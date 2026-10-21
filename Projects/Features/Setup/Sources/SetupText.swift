import Core
import DevEnvironmentInterface
import Foundation

/// 화면 문구. 모두 이 모듈의 `Localizable.xcstrings` 에서 찾는다 (`bundle: .module`).
/// Xcode 버전·경로, 설치할 iOS 버전, 내려받기 숫자(퍼센트·바이트)는 카탈로그를 거치지 않고 그대로(`Text(verbatim:)`) 보인다.
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
        localized: """
        Xcode 가 응답하지 않았거나 시작되지 않았습니다. Xcode 를 설치하거나 업데이트하는 중이면 끝난 뒤 다시 확인을 누르세요. \
        계속 실패하면 Mac 을 재시동하거나 App Store 에서 Xcode 를 다시 설치하세요.
        """,
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
    case .installRuntime:
      String(localized: "iOS 시뮬레이터 설치", bundle: .module)
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

  // MARK: - iOS 시뮬레이터 (Xcode 준비됨)

  /// Xcode 준비됨 화면의 제목. 설치 중·설치 결과 확인 중이면 View 가 이 함수 대신 `installingTitle`·`verifyingInstallTitle` 을 쓴다.
  static func title(for runtime: SetupRuntimeState) -> String {
    switch runtime {
    case .notChecked:
      self.checkingTitle
    case .checked(_, .installed):
      String(localized: "준비가 끝났습니다", bundle: .module)
    case .checked(_, .notInstalled):
      String(localized: "iOS 시뮬레이터를 설치하세요", bundle: .module)
    case .checked(_, .preparing):
      String(localized: "iOS 시뮬레이터를 준비하는 중입니다", bundle: .module)
    case .checked(_, .unusable):
      String(localized: "iOS 시뮬레이터를 쓸 수 없습니다", bundle: .module)
    case .defaultRuntimeUnknown:
      String(localized: "iOS 버전을 확인하지 못했습니다", bundle: .module)
    case .failed:
      String(localized: "iOS 시뮬레이터 상태를 확인하지 못했습니다", bundle: .module)
    }
  }

  /// Xcode 준비됨 화면의 본문. 확인 전이면 nil (진행 표시만).
  static func message(for runtime: SetupRuntimeState) -> String? {
    switch runtime {
    case .notChecked:
      nil
    case .checked(_, .installed):
      String(localized: "이제 iOS 시뮬레이터 기기를 켜고 앱을 설치할 수 있습니다.", bundle: .module)
    case .checked(_, .notInstalled):
      String(
        localized: """
        iOS 시뮬레이터가 이 Mac 에 없습니다. 설치를 누르면 Apple 서버에서 내려받아 설치합니다. \
        수 GB 를 내려받아 시간이 오래 걸릴 수 있고, 인터넷 연결과 Mac 의 저장 공간이 필요합니다.
        """,
        bundle: .module
      )
    case .checked(_, .preparing):
      String(localized: "내려받은 iOS 시뮬레이터를 확인하고 있습니다. 잠시 뒤 다시 확인을 누르세요.", bundle: .module)
    case .checked(_, .unusable):
      String(localized: "설치된 iOS 시뮬레이터를 쓸 수 없는 상태입니다. Mac 을 재시동한 뒤 다시 확인을 누르세요.", bundle: .module)
    case .defaultRuntimeUnknown:
      String(
        localized: "이 Xcode 가 쓰는 iOS 버전을 읽지 못했습니다. App Store 에서 Xcode 를 최신 버전으로 업데이트하거나 다시 설치하세요.",
        bundle: .module
      )
    case .failed:
      String(localized: "다시 확인을 누르세요. 계속 실패하면 Mac 을 재시동한 뒤 다시 시도하세요.", bundle: .module)
    }
  }

  static let installingTitle = String(localized: "iOS 시뮬레이터를 설치하는 중입니다", bundle: .module)
  static let installingMessage = String(localized: "설치가 끝날 때까지 기다리세요. 창을 닫아도 설치는 계속됩니다.", bundle: .module)
  static let verifyingInstallTitle = String(localized: "설치 결과를 확인하는 중…", bundle: .module)
  static let installButton = String(localized: "iOS 시뮬레이터 설치", bundle: .module)
  static let otherVersionNote = String(
    localized: "이미 다른 iOS 버전의 기기가 있으면 설치하지 않고 기기 목록을 열어도 됩니다.",
    bundle: .module
  )
  static let defaultRuntimeLabel = String(localized: "설치할 iOS", bundle: .module)

  // MARK: - 설치 진행

  static func phaseTitle(_ phase: RuntimeInstallProgress.Phase) -> String {
    switch phase {
    case .preparing:
      String(localized: "설치를 준비하는 중…", bundle: .module)
    case .downloading:
      String(localized: "내려받는 중…", bundle: .module)
    case .installing:
      String(localized: "설치하는 중…", bundle: .module)
    }
  }

  /// 내려받기 숫자 줄 (예: `14.9% · 558.6 MB / 3.76 GB`). 내려받기 단계가 아니거나 퍼센트·바이트가 모두 없으면 nil.
  /// 없는 값은 빼고, 바이트는 받은 양과 전체가 모두 있을 때만 보인다 (1000 진법).
  static func downloadDetail(_ progress: RuntimeInstallProgress, locale: Locale) -> String? {
    guard progress.phase == .downloading else { return nil }
    var parts: [String] = []
    if let fraction = progress.fractionCompleted {
      parts.append(fraction.formatted(.percent.precision(.fractionLength(1)).locale(locale)))
    }
    if let completed = progress.completedBytes, let total = progress.totalBytes {
      let style = ByteCountFormatStyle(style: .file, locale: locale)
      parts.append("\(completed.formatted(style)) / \(total.formatted(style))")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  static let cancelInstallButton = String(localized: "취소", bundle: .module)
  static let cancellingLabel = String(localized: "취소하는 중…", bundle: .module)
  static let cannotCancelNote = String(localized: "설치 마무리 단계라 취소할 수 없습니다. 곧 끝납니다.", bundle: .module)
  static let stalledNote = String(
    localized: """
    내려받기가 멈춰 있습니다. 인터넷 연결을 확인하세요. 잠깐 끊긴 경우에는 연결되면 이어서 받습니다. \
    계속 멈춰 있으면 취소한 뒤 다시 설치하세요.
    """,
    bundle: .module
  )
  static let quitAfterCancelNote = String(localized: "취소를 마치면 앱을 종료합니다.", bundle: .module)
  static let quitAfterInstallNote = String(localized: "설치를 마치면 앱을 종료합니다.", bundle: .module)

  // MARK: - 설치 결과

  /// 설치 결과 줄. 설치 중이거나 설치 결과를 확인하는 중이면 View 가 부르지 않는다.
  /// 기본 iOS 가 설치됨이면 방금 설치한 경우(`.finished(.installed)`)만, 설치되지 않았으면 결과마다 문구를 고른다.
  /// 그 밖의 런타임 상태(준비 중·쓸 수 없음·버전 읽기 실패·목록 실패·확인 전)는 상태 제목·본문이 안내하므로 nil.
  static func installResultMessage(for result: SetupInstallResult?, runtime: SetupRuntimeState) -> String? {
    guard let result else { return nil }
    switch runtime {
    case .checked(_, .installed):
      guard result == .finished(.installed) else { return nil }
      return String(localized: "iOS 시뮬레이터를 설치했습니다.", bundle: .module)
    case .checked(_, .notInstalled):
      return self.notInstalledResultMessage(result)
    case .checked(_, .preparing), .checked(_, .unusable), .defaultRuntimeUnknown, .failed, .notChecked:
      return nil
    }
  }

  private static func notInstalledResultMessage(_ result: SetupInstallResult) -> String {
    switch result {
    case .finished:
      String(localized: "설치가 끝났지만 iOS 시뮬레이터가 아직 보이지 않습니다. 잠시 뒤 다시 확인을 누르세요.", bundle: .module)
    case .failed(.cancelled):
      String(localized: "설치를 취소했습니다.", bundle: .module)
    case .failed(.failed):
      String(
        localized: """
        iOS 시뮬레이터를 설치하지 못했습니다. 인터넷 연결과 Mac 의 저장 공간이 충분한지 확인한 뒤 다시 설치를 누르세요. \
        계속 실패하면 Mac 을 재시동한 뒤 다시 시도하세요.
        """,
        bundle: .module
      )
    case .failed(.launchFailed):
      String(
        localized: """
        Xcode 의 설치 도구를 시작하지 못했습니다. Xcode 를 설치하거나 업데이트하는 중이면 끝난 뒤 다시 설치를 누르세요. \
        계속 실패하면 App Store 에서 Xcode 를 다시 설치하세요.
        """,
        bundle: .module
      )
    case .failed(.xcodeNotFound):
      String(localized: "Xcode 를 찾지 못해 설치하지 못했습니다. 화면의 안내에 따라 Xcode 를 설치하세요.", bundle: .module)
    }
  }

  // MARK: - 종료 확인

  static let terminationTitle = String(localized: "iOS 시뮬레이터를 설치하는 중입니다", bundle: .module)
  static let terminationMessage = String(
    localized: """
    지금 종료하면 설치가 취소됩니다. 취소를 마치는 데 몇 초 걸릴 수 있고, 끝나면 앱이 종료됩니다. \
    마무리 단계에 들어갔으면 설치를 마친 뒤 종료합니다.
    """,
    bundle: .module
  )
  static let continueInstallButton = String(localized: "계속 설치", bundle: .module)
  static let quitButton = String(localized: "종료", bundle: .module)
}
