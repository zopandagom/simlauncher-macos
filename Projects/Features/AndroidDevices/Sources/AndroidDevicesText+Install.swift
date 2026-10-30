import AndroidEmulatorInterface
import AndroidPackageInterface
import Core
import Foundation

/// 앱 설치·실행 문구 (행 메뉴, 실행 시트, 알림). 키는 다른 문구와 같은 `Localizable.xcstrings` 에 있다.
/// adb 출력 원문은 경로(사용자 폴더)가 들어 있어 보이지 않고, Client 가 가른 원인으로만 문구를 고른다.
extension AndroidDevicesText {
  // MARK: - 기기 행

  /// 앱 설치 메뉴 제목 (항목은 `installFromFileMenuItem`·`installFromURLMenuItem`·`installFromCatalogMenuItem`).
  static var installAppButton: String {
    String(localized: "앱 설치", bundle: .module)
  }

  static var installFromFileMenuItem: String {
    String(localized: "파일에서 고르기…", bundle: .module)
  }

  static var installAppHelp: String {
    String(
      localized: """
      .apk 파일을 고르거나, https 주소나 등록한 빌드 카탈로그에서 받아 이 기기에 설치하고 바로 실행합니다. \
      이 줄에 .apk 를 끌어다 놓아도 됩니다.
      """,
      bundle: .module
    )
  }

  static var launchAppButton: String {
    String(localized: "앱 실행…", bundle: .module)
  }

  static var launchAppHelp: String {
    String(localized: "이 기기에 설치한 앱 중 하나를 골라 실행합니다.", bundle: .module)
  }

  /// 앱 설치·실행·링크 열기가 막힌 이유 (행 도움말). 고르거나 시트를 연 사이 기기 상태가 바뀐 실패의 본문에도 쓴다.
  static func appActionBlockReason(_ reason: AndroidAppActionBlockReason) -> String {
    switch reason {
    case .notBooted:
      String(
        localized: "기기가 켜져 있을 때만 앱을 설치하거나 실행하고 링크를 열 수 있습니다. 기기를 켠 뒤 다시 시도하세요.",
        bundle: .module
      )
    case .unavailable:
      String(localized: "사용할 수 없는 기기에서는 앱을 설치·실행하거나 링크를 열 수 없습니다", bundle: .module)
    }
  }

  // MARK: - 앱 실행 시트

  static func launchAppSheetTitle(for device: AndroidDeviceLabel) -> String {
    let label = self.label(device)
    return String(localized: "\(label) 기기에서 앱 실행", bundle: .module)
  }

  static var loadingPackages: String {
    String(localized: "설치한 앱 목록을 불러오는 중…", bundle: .module)
  }

  static var noInstalledPackages: String {
    String(localized: "이 기기에 직접 설치한 앱이 없습니다. 앱 설치로 apk 를 먼저 설치하세요.", bundle: .module)
  }

  static var packagePicker: String {
    String(localized: "앱", bundle: .module)
  }

  static var launchConfirmButton: String {
    String(localized: "실행", bundle: .module)
  }

  static var closeButton: String {
    String(localized: "닫기", bundle: .module)
  }

  // MARK: - 알림

  /// 앱 작업(설치·실행·링크 열기) 알림의 제목. `title(for:)` 가 네 케이스를 한 줄로 넘긴다 (복잡도를 나눈다).
  static func appNoticeTitle(for notice: AndroidDevicesNotice?) -> String {
    switch notice {
    case let .installedButNotLaunched(device, _):
      let label = self.label(device)
      return String(localized: "\(label) 기기에 앱을 설치했지만 실행하지 못했습니다", bundle: .module)
    case let .launchFailed(device, _):
      let label = self.label(device)
      return String(localized: "\(label) 기기에서 앱을 실행하지 못했습니다", bundle: .module)
    case let .openURLFailed(device, _):
      return self.openURLNoticeTitle(for: device)
    case let .installFailed(device, _):
      let label = self.label(device)
      return String(localized: "\(label) 기기에 앱을 설치하지 못했습니다", bundle: .module)
    default:
      return ""
    }
  }

  /// 앱 작업 알림의 본문. `message(for:)` 가 네 케이스를 한 줄로 넘긴다.
  static func appNoticeMessage(for notice: AndroidDevicesNotice) -> String {
    switch notice {
    case let .installFailed(_, failure):
      self.message(for: failure)
    case let .installedButNotLaunched(_, error):
      self.installedButNotLaunchedMessage(for: error)
    case let .launchFailed(_, failure), let .openURLFailed(_, failure):
      self.message(for: failure)
    default:
      ""
    }
  }

  static func message(for failure: AndroidAppInstallFailure) -> String {
    switch failure {
    case .multipleItems:
      String(localized: "한 번에 apk 하나만 설치할 수 있습니다. apk 하나만 끌어다 놓으세요.", bundle: .module)
    case let .package(error):
      self.message(for: error)
    case let .rejected(problem):
      self.message(for: problem)
    case let .deviceNotReady(reason):
      self.appActionBlockReason(reason)
    case let .emulator(error):
      self.message(for: error) ?? ""
    case let .download(error, origin):
      self.downloadMessage(for: error, origin: origin)
    case let .downloadedPackage(error, isWebPage, origin):
      self.downloadedPackageMessage(for: error, isWebPage: isWebPage, origin: origin)
    }
  }

  static func message(for failure: AndroidAppActionFailure) -> String {
    switch failure {
    case let .deviceNotReady(reason):
      self.appActionBlockReason(reason)
    case let .emulator(error):
      self.message(for: error) ?? ""
    }
  }

  /// 설치 뒤 실행 실패. 실행할 화면이 없으면 설치는 됐다는 문구, 그 밖은 에러 본문.
  static func installedButNotLaunchedMessage(for error: AndroidEmulatorError) -> String {
    guard error == .launchFailed(.noLauncherActivity) else {
      return self.message(for: error) ?? ""
    }
    return String(
      localized: "앱을 설치했지만 홈 화면에서 여는 화면이 없어 실행하지 않았습니다. 기기의 앱 목록이나 다른 앱에서 여세요.",
      bundle: .module
    )
  }

  /// apk 검사 실패의 본문.
  static func message(for error: AndroidPackageError) -> String {
    switch error {
    case .notLocalFile:
      String(localized: "웹 주소는 끌어다 놓아 설치할 수 없습니다. 파일로 받은 뒤 .apk 파일을 끌어다 놓으세요.", bundle: .module)
    case .fileNotFound:
      String(localized: "설치할 apk 파일을 찾을 수 없습니다. 파일이 옮겨지거나 지워졌을 수 있습니다. 파일을 다시 골라 주세요.", bundle: .module)
    case .appBundle:
      String(
        localized: """
        .aab(App Bundle) 파일은 기기에 바로 설치할 수 없습니다. \
        개발자에게 설치용 .apk 파일(예: Android Studio 의 Build APK, Gradle assembleDebug)을 요청하세요.
        """,
        bundle: .module
      )
    case .splitPackage:
      String(localized: "여러 apk 를 묶은 파일(.apks·.xapk·.apkm)은 설치할 수 없습니다. 하나로 된 .apk 파일을 요청하세요.", bundle: .module)
    case .notAPK:
      String(localized: ".apk 파일만 설치할 수 있습니다. 개발자에게 Android 용 .apk 파일을 요청하세요.", bundle: .module)
    case .unreadable:
      self.apkUnreadable
    case .unsafeEntry:
      String(localized: "apk 안에 잘못된 경로나 링크가 있어 설치하지 않았습니다. 믿을 수 있는 곳에서 받은 파일인지 확인하세요.", bundle: .module)
    case .unsigned:
      String(localized: "서명되지 않은 apk 라 설치할 수 없습니다. 개발자에게 서명된 apk(디버그 서명도 됩니다)를 요청하세요.", bundle: .module)
    case .inspectionUnavailable:
      String(localized: "apk 를 검사할 임시 폴더를 준비하지 못했습니다. 잠시 뒤 다시 시도하고, 계속되면 Mac 을 다시 시작해 보세요.", bundle: .module)
    }
  }

  /// apk 가 손상됐다 (검사의 읽기 실패와 기기의 `INSTALL_PARSE_FAILED_NOT_APK` 공용).
  private static var apkUnreadable: String {
    String(localized: "apk 를 읽지 못했습니다. 파일이 손상되었거나 끝까지 받지 못했을 수 있습니다. 파일을 다시 받아 주세요.", bundle: .module)
  }

  /// 기기 판정 거절의 본문. 값은 판정 결과에서만 가져온다 (기기 ABI 를 하드코딩하지 않는다. Intel Mac 은 x86_64).
  static func message(for problem: AndroidInstallProblem) -> String {
    switch problem {
    case let .noMatchingABI(app, device):
      let deviceABIs = device.joined(separator: ", ")
      let appABIs = app.joined(separator: ", ")
      let first = device.first ?? deviceABIs
      return String(
        localized: "이 앱에는 이 기기(\(deviceABIs))에서 실행할 코드가 없습니다 (앱: \(appABIs)). 개발자에게 \(first) 용 코드가 포함된 apk 를 요청하세요.",
        bundle: .module
      )
    case let .requiresNewerAPI(required, device):
      return String(
        localized: "이 앱은 Android API \(required) 이상에서 실행됩니다. 이 기기는 API \(device) 입니다. 더 높은 API 의 기기를 만들어 설치하세요.",
        bundle: .module
      )
    }
  }

  // MARK: - adb 앱 명령 실패

  /// 앱 설치·실행·링크 열기 명령의 실패 본문. 다른 분류면 nil. `message(for: AndroidEmulatorError)` 가 넘긴다.
  static func appMessage(for error: AndroidEmulatorError) -> String? {
    switch error {
    case .deviceNotBooted:
      String(localized: "기기가 꺼졌거나 아직 켜지는 중이라 하지 못했습니다. 기기가 켜진 뒤 다시 시도하세요.", bundle: .module)
    case let .installFailed(failure):
      self.message(for: failure)
    case .installTimedOut:
      String(localized: "설치가 10분 안에 끝나지 않았습니다. 기기가 응답하는지 확인하고 다시 시도하세요.", bundle: .module)
    case .launchFailed(.noLauncherActivity):
      String(localized: "이 앱에는 홈 화면에서 여는 화면이 없어 실행할 수 없습니다.", bundle: .module)
    case .launchFailed(.notInstalled):
      String(localized: "이 앱이 기기에 설치되어 있지 않습니다. 앱 설치로 다시 설치하세요.", bundle: .module)
    case .urlNotHandled:
      self.urlNotHandledMessage
    case .appCommandFailed:
      String(localized: "기기가 요청을 처리하지 못했습니다. 잠시 뒤 다시 시도하고, 계속되면 기기를 껐다 켜 보세요.", bundle: .module)
    default:
      nil
    }
  }

  /// `adb install` 의 `INSTALL_FAILED_*`·`INSTALL_PARSE_FAILED_*` 원인별 본문.
  static func message(for failure: AndroidInstallFailure) -> String {
    switch failure {
    case .olderSDK:
      String(localized: "이 앱은 이 기기보다 높은 Android API 에서 실행됩니다. 더 높은 API 의 기기를 만들어 설치하세요.", bundle: .module)
    case .noMatchingABIs:
      String(localized: "이 앱에는 이 기기에서 실행할 코드가 없습니다. 개발자에게 이 기기의 ABI 용 코드가 포함된 apk 를 요청하세요.", bundle: .module)
    case .updateIncompatible:
      String(
        localized: "기기에 서명이 다른 같은 앱이 이미 있습니다. 기기에서 그 앱을 지운 뒤(앱 아이콘을 길게 눌러 제거) 다시 설치하세요. 데이터도 함께 지워집니다.",
        bundle: .module
      )
    case .versionDowngrade:
      String(localized: "기기에 더 새 버전이 설치되어 있어 이전 버전으로 바꿀 수 없습니다. 기기에서 앱을 지운 뒤 다시 설치하세요.", bundle: .module)
    case .noCertificates:
      String(localized: "apk 의 서명을 확인하지 못했습니다. 파일이 손상되었거나 서명 후 바뀌었을 수 있습니다. 파일을 다시 받아 주세요.", bundle: .module)
    case .notAPK:
      self.apkUnreadable
    case .deprecatedSDK:
      String(
        localized: "이 앱은 너무 오래된 Android 버전용으로 만들어져 이 기기에 설치할 수 없습니다. 개발자에게 최신 targetSdk 로 빌드한 apk 를 요청하세요.",
        bundle: .module
      )
    case .insufficientStorage, .conflict, .missingSharedLibrary, .testOnly, .missingSplit, .other:
      self.uncommonInstallMessage(for: failure)
    }
  }

  /// 드문 설치 실패의 본문. `message(for: AndroidInstallFailure)` 가 넘긴다 (복잡도를 나눈다).
  private static func uncommonInstallMessage(for failure: AndroidInstallFailure) -> String {
    switch failure {
    case .insufficientStorage:
      String(localized: "기기의 저장 공간이 부족합니다. 기기에서 쓰지 않는 앱을 지우거나 기기를 초기화한 뒤 다시 시도하세요.", bundle: .module)
    case .conflict:
      String(
        localized: "기기의 다른 앱과 충돌해 설치하지 못했습니다(같은 권한·데이터 제공자 이름). 개발자에게 알리거나, 충돌하는 앱을 지운 뒤 다시 시도하세요.",
        bundle: .module
      )
    case .missingSharedLibrary:
      String(localized: "이 기기에 없는 시스템 라이브러리가 필요한 앱입니다. 개발자에게 필요한 기기 종류를 확인하세요.", bundle: .module)
    case .testOnly:
      String(localized: "테스트 전용 apk 라 설치하지 못했습니다. 개발자에게 일반 디버그 apk 를 요청하세요.", bundle: .module)
    case .missingSplit:
      String(localized: "여러 apk 로 나뉜 앱의 일부라 이것만 설치할 수 없습니다. 하나로 된 .apk 파일을 요청하세요.", bundle: .module)
    case let .other(code?):
      String(localized: "설치하지 못했습니다 (\(code)). 파일을 다시 골라 시도하고, 계속되면 이 코드를 개발자에게 알려 주세요.", bundle: .module)
    case .other(nil):
      String(localized: "설치하지 못했습니다 (원인을 알 수 없음). 파일을 다시 골라 시도하고, 계속되면 개발자에게 알려 주세요.", bundle: .module)
    default:
      ""
    }
  }
}
