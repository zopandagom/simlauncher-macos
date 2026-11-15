import Foundation

/// "업데이트" 절의 문구. 키는 다른 문구와 같은 `Localizable.xcstrings` 에 있다.
extension SettingsText {
  static var updateSectionTitle: String {
    String(localized: "업데이트", bundle: .module)
  }

  static var automaticUpdateCheckToggle: String {
    String(localized: "새 버전을 자동으로 확인", bundle: .module)
  }

  static var automaticUpdateCheckCaption: String {
    String(
      localized: """
      켜 두면 SimLauncher 를 켤 때와 다른 앱에서 돌아올 때, 마지막 확인에서 하루가 지났으면 \
      GitHub 에서 최신 버전 정보를 받아 새 버전이 있으면 메인 창 위쪽에 알립니다 \
      (GitHub 에 닿지 못했으면 한 시간 뒤 다시 시도합니다). \
      꺼도 메뉴 'SimLauncher > 업데이트 확인…' 으로 직접 확인할 수 있습니다.
      """,
      bundle: .module
    )
  }

  static var automaticUpdateCheckLockedNote: String {
    String(localized: "관리자가 정한 설정이라 이 Mac 에서 바꿀 수 없습니다.", bundle: .module)
  }
}
