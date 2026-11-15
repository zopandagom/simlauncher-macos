import AndroidEmulatorInterface
import Core
import Foundation

/// 설치된 앱("설치된 앱…" 시트) 문구. "(공통)" 문구는 iOS 기기 목록(Launcher)의 `LauncherText+InstalledApps.swift` 와 같은
/// 키·값이다 (`LauncherTextSyncTests` 가 확인한다). 목록 읽기 중·실패·빈 목록·다시 읽기·실패 이유는 테스트 조건 앱 구역의 문구를
/// 다시 쓴다.
extension AndroidDevicesText {
  // MARK: - 기기 행

  /// (공통)
  static var installedAppsButton: String {
    String(localized: "설치된 앱…", bundle: .module)
  }

  /// (공통)
  static var installedAppsHelp: String {
    String(localized: "이 기기에 설치한 앱을 보고 지웁니다.", bundle: .module)
  }

  /// (공통) "설치된 앱…" 버튼이 막힌 이유 (툴팁). 기기 규칙은 앱 작업과 같다 (켜는 중은 `.notBooted`).
  static func installedAppsBlockReason(_ reason: AndroidAppActionBlockReason) -> String {
    switch reason {
    case .notBooted:
      String(localized: "켜진 기기에서만 설치된 앱을 볼 수 있습니다. 기기를 켠 뒤 다시 시도하세요", bundle: .module)
    case .unavailable:
      String(localized: "사용할 수 없는 기기에서는 설치된 앱을 볼 수 없습니다", bundle: .module)
    }
  }

  // MARK: - 시트

  /// (공통) 시트 제목. 기기 이름은 번역하지 않는 값이다.
  static func installedAppsSheetTitle(for device: AndroidDeviceLabel) -> String {
    String(localized: "\(device.name) 설치된 앱", bundle: .module)
  }

  /// (공통)
  static var installedAppsSheetNote: String {
    String(localized: "직접 설치한 앱만 보입니다. 지운 앱은 다시 설치해야 합니다.", bundle: .module)
  }

  /// (공통) 고른 앱을 지우는 버튼 (확인 대화상자를 띄운다).
  static var removeAppButton: String {
    String(localized: "삭제…", bundle: .module)
  }

  /// (공통) 확인 대화상자의 지우기 버튼.
  static var removeAppConfirmButton: String {
    String(localized: "삭제", bundle: .module)
  }

  /// (공통) 진행 줄. 패키지 이름은 번역하지 않는 값이다.
  static func removingApp(_ name: String) -> String {
    String(localized: "\(name) 앱을 지우는 중…", bundle: .module)
  }

  /// (공통) 확인 대화상자 제목 (패키지 이름).
  static func removeAppConfirmationTitle(_ name: String) -> String {
    String(localized: "\(name) 앱을 지울까요?", bundle: .module)
  }

  /// 확인 대화상자 본문: 기기(이름·API)를 보여 다른 기기의 앱을 지우는 실수를 막는다 (패키지 이름은 제목에 있다).
  static func removeAppConfirmationMessage(on device: AndroidDeviceLabel) -> String {
    String(
      localized: "\(self.label(device)) 기기에서 앱과 앱 데이터를 지웁니다. 실행 중이면 종료됩니다. 되돌릴 수 없습니다.",
      bundle: .module
    )
  }

  /// 마지막 동작의 결과 줄. 실패 이유는 테스트 조건 시트와 같은 문구다 (꺼짐은 이 시트의 문구, 그 밖은 Android 기기 오류 문구).
  static func installedAppsMessage(_ message: AndroidInstalledAppsMessage) -> String {
    switch message {
    case let .removed(package):
      self.appRemoved(package.rawValue)
    case let .failed(.remove(package), error):
      self.removeAppFailed(package.rawValue, reason: self.testConditionsFailure(error))
    }
  }

  /// (공통)
  static func appRemoved(_ name: String) -> String {
    String(localized: "\(name) 앱을 지웠습니다.", bundle: .module)
  }

  /// (공통)
  static func removeAppFailed(_ name: String, reason: String) -> String {
    String(localized: "\(name) 앱을 지우지 못했습니다. \(reason)", bundle: .module)
  }
}
