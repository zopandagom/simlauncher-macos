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
      localized: "시뮬레이터용 .app 이나 그 .app 을 압축한 zip 을 골라 이 기기에 설치하고 바로 실행합니다. 이 줄에 끌어다 놓아도 됩니다.",
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
      String(localized: "한 번에 앱 하나만 설치할 수 있습니다. .app 이나 zip 하나만 끌어다 놓으세요.", bundle: .module)
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

  /// 번들 검사·zip 풀기 실패의 본문. 케이스마다 정확히 한 분류가 문구를 돌려준다.
  static func message(for error: AppBundleError) -> String {
    self.bundleFileMessage(for: error) ?? self.zipMessage(for: error) ?? self.appInvalid
  }

  /// 고른 항목의 경로·종류나 .app 내용 문제 (검사와 풀기 공용). 다른 분류면 nil.
  static func bundleFileMessage(for error: AppBundleError) -> String? {
    switch error {
    case .notLocalFile:
      String(localized: "웹 주소는 아직 설치할 수 없습니다. 내려받은 .app 이나 zip 파일을 골라 주세요.", bundle: .module)
    case .fileNotFound:
      self.appFileNotFound
    case .ipaFile:
      String(localized: ".ipa 파일은 설치할 수 없습니다. 시뮬레이터용으로 빌드한 .app 파일을 받아 주세요.", bundle: .module)
    case .notAppBundle:
      String(
        localized: """
        .app 이나 zip 이 아닌 항목은 설치할 수 없습니다. \
        시뮬레이터용으로 빌드한 .app 이나 그 .app 을 압축한 zip 을 골라 주세요.
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
    case .zipUnreadable, .zipWithoutApp, .zipWithMultipleApps, .zipUnsafeEntry, .insufficientDiskSpace,
         .extractionUnavailable:
      nil
    }
  }

  /// zip 풀기 실패. 다른 분류면 nil.
  static func zipMessage(for error: AppBundleError) -> String? {
    switch error {
    case .zipUnreadable:
      String(
        localized: """
        zip 파일을 풀지 못했습니다. 파일이 손상되었거나, 끝까지 받지 못했거나, 비밀번호가 걸려 있을 수 있습니다. \
        파일을 다시 받아 주세요.
        """,
        bundle: .module
      )
    case .zipWithoutApp:
      String(localized: "zip 맨 위에 .app 이 없습니다. 시뮬레이터용 .app 을 바로 압축한 zip 을 골라 주세요.", bundle: .module)
    case .zipWithMultipleApps:
      String(localized: "zip 맨 위에 .app 이 여러 개 있습니다. .app 하나만 압축한 zip 을 골라 주세요.", bundle: .module)
    case .zipUnsafeEntry:
      // 풀기 전 이름 검사와 푼 뒤 링크 검사(대상 없음·루프 포함)가 같은 문구를 쓴다.
      String(
        localized: """
        zip 안에 잘못된 경로나 링크(압축을 푸는 폴더 밖이나 없는 곳을 가리키는 항목)가 있어 설치하지 않았습니다. \
        믿을 수 있는 곳에서 받은 파일인지 확인하세요.
        """,
        bundle: .module
      )
    case .insufficientDiskSpace:
      String(localized: "Mac 의 저장 공간이 부족해 zip 을 풀지 못했습니다. 공간을 확보한 뒤 다시 시도하세요.", bundle: .module)
    case .extractionUnavailable:
      String(
        localized: "zip 을 풀 임시 폴더를 준비하지 못했습니다. 잠시 뒤 다시 시도하고, 계속되면 Mac 을 다시 시작해 보세요.",
        bundle: .module
      )
    case .notLocalFile, .fileNotFound, .ipaFile, .notAppBundle, .macOSApp, .invalidBundle:
      nil
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

  /// 고른 .app·zip 이 없다 (검사·풀기 `.fileNotFound`, 설치 명령 `.appNotFound` 공용).
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
