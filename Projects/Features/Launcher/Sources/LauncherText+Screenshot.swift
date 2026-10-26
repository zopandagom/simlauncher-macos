import Core
import Foundation
import SimulatorInterface
import WorkspaceInterface

/// 스크린샷 문구. 키는 다른 문구와 같은 `Localizable.xcstrings` 에 있다.
extension LauncherText {
  // MARK: - 기기 행

  static var screenshotButton: String {
    String(localized: "스크린샷", bundle: .module)
  }

  static var screenshotHelp: String {
    String(localized: "기기 화면을 사진 폴더의 SimLauncher 폴더에 PNG 파일로 저장하고 Finder 에서 보여 줍니다", bundle: .module)
  }

  static var takingScreenshotLabel: String {
    String(localized: "스크린샷을 찍는 중…", bundle: .module)
  }

  /// 스크린샷 버튼이 막힌 이유 (툴팁).
  static func screenshotBlockReason(_ reason: ScreenshotBlockReason) -> String {
    switch reason {
    case .notBooted:
      String(localized: "켜진 기기에서만 스크린샷을 찍을 수 있습니다. 기기를 켠 뒤 다시 시도하세요", bundle: .module)
    case .unavailable:
      String(localized: "사용할 수 없는 기기에서는 스크린샷을 찍을 수 없습니다", bundle: .module)
    }
  }

  // MARK: - 알림

  /// 스크린샷 실패 알림의 제목. `rowTaskNoticeTitle(for:device:)` 가 두 케이스를 넘긴다.
  static func screenshotNoticeTitle(for notice: LauncherNotice?, device: LauncherNotice.Device) -> String {
    if case .screenshotRevealFailed = notice {
      return String(
        localized: "“\(device.name)” (\(device.runtimeName)) 기기의 스크린샷을 저장했지만 Finder 에서 보여 주지 못했습니다",
        bundle: .module
      )
    }
    return String(localized: "“\(device.name)” (\(device.runtimeName)) 기기의 스크린샷을 저장하지 못했습니다", bundle: .module)
  }

  static func message(for failure: ScreenshotFailure) -> String {
    switch failure {
    case let .workspace(error):
      self.message(for: error)
    case .simulator(.deviceNotBooted):
      // 설치·실행 문구("앱을 설치하려면…")가 아니라 스크린샷 문구로 알린다.
      String(localized: "기기가 켜져 있지 않아 스크린샷을 찍지 못했습니다. 기기를 켠 뒤 다시 시도하세요.", bundle: .module)
    case let .simulator(error):
      self.message(for: error)
    }
  }

  static func message(for error: WorkspaceError) -> String {
    switch error {
    case .folderUnavailable:
      String(
        localized: """
        사진 폴더 안에 SimLauncher 폴더를 만들거나 그 안에 파일을 쓸 수 없습니다. \
        Finder 에서 사진 폴더에 SimLauncher 라는 이름의 파일이 있지 않은지, 디스크 공간이 남아 있는지 확인한 뒤 다시 시도하세요.
        """,
        bundle: .module
      )
    case .fileNameUnavailable:
      String(
        localized: """
        같은 이름의 스크린샷이 너무 많아 새 파일 이름을 정하지 못했습니다. \
        사진 폴더의 SimLauncher 폴더에서 이전 스크린샷을 다른 곳으로 옮긴 뒤 다시 시도하세요.
        """,
        bundle: .module
      )
    case .fileNotFound:
      String(
        localized: """
        저장한 스크린샷 파일을 찾지 못했습니다. 파일이 옮겨지거나 지워졌을 수 있습니다. \
        Finder 에서 사진 폴더의 SimLauncher 폴더를 열어 확인하세요.
        """,
        bundle: .module
      )
    }
  }
}
