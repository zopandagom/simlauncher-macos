import Core
import Foundation

/// 행 "레이아웃 보기" 문구. 키는 다른 문구와 같은 `Localizable.xcstrings` 에 있다.
/// 창 안 문구(준비 중·읽는 중·실패 등)는 LayoutInspector Feature 가 갖는다. AndroidDevices 의 같은 문구와 값이 같다 (동기화 테스트).
extension LauncherText {
  static var layoutButton: String {
    String(localized: "레이아웃 보기", bundle: .module)
  }

  static var layoutHelp: String {
    String(localized: "앱 화면의 뷰 테두리와 위치·크기를 봅니다", bundle: .module)
  }

  /// 기기 iOS 가 러너의 최소 버전보다 낮을 때 "레이아웃 보기" 툴팁.
  static var layoutUnsupportedOS: String {
    String(
      localized: "iOS \(IOSLayoutRunner.minimumOSVersion.major) 이상 기기에서만 레이아웃을 볼 수 있습니다",
      bundle: .module
    )
  }

  /// "레이아웃 보기" 가 막힌 이유 (툴팁). 기기 규칙은 스크린샷과 같다.
  static func layoutBlockReason(_ reason: ScreenshotBlockReason) -> String {
    switch reason {
    case .notBooted:
      String(localized: "켜진 기기에서만 레이아웃을 볼 수 있습니다. 기기를 켠 뒤 다시 시도하세요", bundle: .module)
    case .unavailable:
      String(localized: "사용할 수 없는 기기에서는 레이아웃을 볼 수 없습니다", bundle: .module)
    }
  }
}
