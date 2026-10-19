import AppBundleInterface
import Core
import Foundation
import SimulatorInterface

/// 앱 설치 문구. 키는 다른 문구와 같은 `Localizable.xcstrings` 에 있다.
extension LauncherText {
  // MARK: - 기기 행

  static var installAppButton: String {
    String(localized: "앱 설치…", bundle: .module)
  }

  static var installAppHelp: String {
    String(
      localized: "시뮬레이터용 .app 을 골라 이 기기에 설치하고 바로 실행합니다. .app 을 이 줄에 끌어다 놓아도 됩니다.",
      bundle: .module
    )
  }

  static var installingLabel: String {
    String(localized: "앱을 설치하는 중…", bundle: .module)
  }

  /// 앱 설치 버튼이 막힌 이유. 검사하는 사이 기기 상태가 바뀐 실패의 본문에도 쓴다.
  static func installBlockReason(_ reason: AppInstallBlockReason) -> String {
    switch reason {
    case .unavailable:
      String(localized: "사용할 수 없는 기기에는 앱을 설치할 수 없습니다", bundle: .module)
    case .stateChanging:
      String(localized: "기기를 켜거나 끄는 중에는 앱을 설치할 수 없습니다. 끝난 뒤 다시 시도하세요", bundle: .module)
    }
  }

  // MARK: - 알림

  /// 설치·실행 실패 알림의 제목. `title(for:)` 가 두 케이스를 한 줄로 넘긴다.
  static func appNoticeTitle(for notice: LauncherNotice?, device: LauncherNotice.Device) -> String {
    if case .launchFailed = notice {
      return String(
        localized: "“\(device.name)” (\(device.runtimeName)) 기기에 앱을 설치했지만 실행하지 못했습니다",
        bundle: .module
      )
    }
    return String(localized: "“\(device.name)” (\(device.runtimeName)) 기기에 앱을 설치하지 못했습니다", bundle: .module)
  }

  static func message(for failure: AppInstallFailure) -> String {
    switch failure {
    case .multipleItems:
      String(localized: "한 번에 앱 하나만 설치할 수 있습니다. .app 하나만 끌어다 놓으세요.", bundle: .module)
    case let .bundle(error):
      self.message(for: error)
    case let .rejected(problem):
      self.message(for: problem)
    case let .deviceNotReady(reason):
      self.installBlockReason(reason)
    case let .simulator(error):
      self.message(for: error)
    }
  }

  static func message(for error: AppBundleError) -> String {
    switch error {
    case .notLocalFile:
      String(localized: "웹 주소는 아직 설치할 수 없습니다. 내려받아 압축을 푼 .app 을 골라 주세요.", bundle: .module)
    case .fileNotFound:
      self.appFileNotFound
    case .ipaFile:
      String(localized: ".ipa 파일은 설치할 수 없습니다. 시뮬레이터용으로 빌드한 .app 파일을 받아 주세요.", bundle: .module)
    case .notAppBundle:
      // 2-B 에서 zip 을 받으면 고친다.
      String(
        localized: """
        .app 이 아닌 항목은 설치할 수 없습니다. zip 파일이면 Finder 에서 풀어 나온 .app 을, \
        아니면 시뮬레이터용으로 빌드한 .app 을 골라 주세요.
        """,
        bundle: .module
      )
    case .macOSApp:
      String(
        localized: "Mac 용 앱은 iOS 시뮬레이터에 설치할 수 없습니다. 시뮬레이터용으로 빌드한 iOS 앱(.app)을 골라 주세요.",
        bundle: .module
      )
    case .invalidBundle:
      self.appInvalid
    }
  }

  static func message(for problem: AppInstallProblem) -> String {
    switch problem {
    case .notSimulatorBuild:
      String(localized: "iOS 시뮬레이터용 빌드가 아닙니다. 개발자에게 시뮬레이터용으로 빌드한 .app 을 요청하세요.", bundle: .module)
    case .missingArchitecture(.arm64):
      String(
        localized: """
        이 앱에는 Apple 실리콘 Mac 의 시뮬레이터에서 실행할 코드(arm64)가 없습니다. \
        개발자에게 arm64 가 포함된 시뮬레이터 빌드를 요청하세요.
        """,
        bundle: .module
      )
    case .missingArchitecture(.x86_64):
      String(
        localized: """
        이 앱에는 Intel Mac 의 시뮬레이터에서 실행할 코드(x86_64)가 없습니다. \
        개발자에게 x86_64 가 포함된 시뮬레이터 빌드를 요청하세요.
        """,
        bundle: .module
      )
    case let .requiresNewerOS(version):
      String(localized: "이 앱은 iOS \(version.description) 이상에서 실행됩니다. 더 높은 iOS 버전의 기기에 설치하세요.", bundle: .module)
    }
  }

  /// 앱 설치·실행 명령의 실패. 다른 분류면 nil.
  static func appCommandMessage(for error: SimulatorError) -> String? {
    switch error {
    case .deviceNotBooted:
      String(localized: "기기가 켜져 있지 않아 앱을 설치하거나 실행하지 못했습니다. 기기를 켠 뒤 다시 시도하세요.", bundle: .module)
    case .appNotFound:
      self.appFileNotFound
    case .appInvalid:
      self.appInvalid
    case .appIncompatible:
      String(
        localized: "이 기기에서 실행할 수 없는 빌드입니다. 시뮬레이터용으로 빌드했는지, 이 기기 종류(iPhone·iPad)를 지원하는지 개발자에게 확인하세요.",
        bundle: .module
      )
    case .appRequiresNewerOS:
      String(localized: "이 앱은 이 기기보다 높은 iOS 버전이 필요합니다. 더 높은 iOS 버전의 기기에 설치하세요.", bundle: .module)
    case .appNotInstalled:
      String(localized: "설치한 앱을 기기에서 찾지 못해 실행하지 못했습니다. 다시 설치해 보세요.", bundle: .module)
    case .appLaunchFailed:
      String(
        localized: "앱이 시작되지 않았거나 시작하자마자 종료되었습니다. 시뮬레이터에서 앱 아이콘을 눌러 다시 실행해 보고, 계속되면 앱 개발자에게 알려 주세요.",
        bundle: .module
      )
    case .developerToolsUnavailable, .deviceNotFound, .deviceNotShutdown, .creationOptionUnavailable,
         .invalidDeviceName,
         .simulatorAppNotFound, .unexpectedOutput, .creationResultUnknown, .commandFailed:
      nil
    }
  }

  /// 고른 .app 이 없다 (검사 `.fileNotFound`, 설치 명령 `.appNotFound` 공용).
  static var appFileNotFound: String {
    String(localized: "고른 파일을 찾을 수 없습니다. 옮기거나 지우지 않았는지 확인한 뒤 다시 골라 주세요.", bundle: .module)
  }

  /// .app 의 정보·실행 파일을 읽지 못했다 (검사 `.invalidBundle`, 설치 명령 `.appInvalid` 공용).
  static var appInvalid: String {
    String(
      localized: "앱 정보(Info.plist)나 실행 파일을 읽지 못했습니다. 빌드가 끝까지 완료된 .app 인지 확인하거나 파일을 다시 받아 주세요.",
      bundle: .module
    )
  }
}
