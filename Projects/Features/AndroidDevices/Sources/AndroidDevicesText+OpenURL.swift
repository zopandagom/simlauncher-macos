import AndroidEmulatorInterface
import Core
import Foundation

/// 링크 열기 문구. 버튼·입력란·예시·열기 버튼·입력 문제·받을 앱 없음 문장은 iOS 기기 목록(Launcher)과 같은 키·값이다
/// (Feature 끼리 공유하지 않아 따로 두고 `LinkProblemSyncTests` 가 묶는다). 도움말·시트 제목·알림 제목은 Android 문장이다.
/// 키는 다른 문구와 같은 `Localizable.xcstrings` 에 있다.
extension AndroidDevicesText {
  // MARK: - 기기 행

  static var openURLButton: String {
    String(localized: "링크 열기…", bundle: .module)
  }

  static var openURLHelp: String {
    String(localized: "앱 스킴 링크(딥링크)나 웹 주소를 입력해 이 기기에서 엽니다.", bundle: .module)
  }

  // MARK: - 시트

  static func openURLSheetTitle(for device: AndroidDeviceLabel) -> String {
    let label = self.label(device)
    return String(localized: "\(label) 기기에서 링크 열기", bundle: .module)
  }

  static var linkField: String {
    String(localized: "링크", bundle: .module)
  }

  static var linkPrompt: String {
    String(localized: "예: myapp://item/1 또는 https://example.com", bundle: .module)
  }

  static var openURLConfirmButton: String {
    String(localized: "열기", bundle: .module)
  }

  /// 입력란 아래 안내. 비어 있으면 문구 없이 열기 버튼만 비활성이다 (nil).
  /// iOS 링크 열기(Launcher)와 같은 키·값이다 (`LinkProblemSyncTests` 가 묶는다).
  static func linkProblem(_ problem: DeepLinkProblem) -> String? {
    switch problem {
    case .empty:
      nil
    case .malformed:
      String(
        localized: """
        링크로 읽을 수 없습니다. 앞에 myapp:// 나 https:// 같은 스킴이 있는지, \
        스킴과 호스트(:// 앞뒤)에 공백이나 쓸 수 없는 문자가 없는지 확인하세요.
        """,
        bundle: .module
      )
    case .missingScheme:
      String(localized: "링크 앞에 myapp:// 나 https:// 같은 스킴을 붙여 입력하세요.", bundle: .module)
    }
  }

  // MARK: - 알림

  static func openURLNoticeTitle(for device: AndroidDeviceLabel) -> String {
    let label = self.label(device)
    return String(localized: "\(label) 기기에서 링크를 열지 못했습니다", bundle: .module)
  }

  /// 링크를 받을 앱이 없다 (`am start` 의 `unable to resolve Intent`). iOS 의 같은 실패와 같은 키·값이다.
  static var urlNotHandledMessage: String {
    String(
      localized: """
      이 링크를 열 수 있는 앱이 기기에 없습니다. \
      링크를 처리할 앱을 이 기기에 먼저 설치했는지, 링크의 스킴(:// 앞부분) 철자가 맞는지 확인하세요.
      """,
      bundle: .module
    )
  }
}
