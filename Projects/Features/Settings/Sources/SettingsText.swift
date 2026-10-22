import Core
import Foundation

/// 설정 창 문구. 모두 이 모듈의 `Localizable.xcstrings` 에서 찾는다 (`bundle: .module`).
/// 저장된 주소와 카탈로그 id·필드 이름은 여기를 거치지 않고 그대로 보이거나 보간 인자로 들어간다.
enum SettingsText {
  // MARK: - 화면

  static var catalogSectionTitle: String {
    String(localized: "빌드 카탈로그", bundle: .module)
  }

  static var lockedNote: String {
    String(
      localized: "관리자가 정한 목록이라 이 Mac 에서 바꿀 수 없습니다. 바꾸려면 Mac 을 관리하는 담당자에게 문의하세요.",
      bundle: .module
    )
  }

  static var emptyList: String {
    String(localized: "등록된 카탈로그가 없습니다.", bundle: .module)
  }

  static var urlField: String {
    String(localized: "카탈로그 주소", bundle: .module)
  }

  static var urlPrompt: String {
    String(localized: "예: https://example.com/catalog.json", bundle: .module)
  }

  static var urlGuide: String {
    String(
      localized: "catalog.json 의 https 주소를 입력하세요. 등록할 때 한 번 받아 형식을 확인합니다. 로그인이 필요한 주소는 쓸 수 없습니다.",
      bundle: .module
    )
  }

  static var addButton: String {
    String(localized: "등록", bundle: .module)
  }

  static var checkingLabel: String {
    String(localized: "카탈로그를 확인하는 중…", bundle: .module)
  }

  static var cancelButton: String {
    String(localized: "취소", bundle: .module)
  }

  static var removeAccessibilityLabel: String {
    String(localized: "삭제", bundle: .module)
  }

  // MARK: - 입력란·목록 안내

  /// 입력란 아래 안내. 비어 있으면 문구 없이 버튼만 비활성이다 (nil).
  static func draftProblem(_ problem: CatalogDraftProblem) -> String? {
    switch problem {
    case .url(.empty):
      nil
    case .url(.malformed):
      String(localized: "주소로 읽을 수 없습니다. 공백이나 쓸 수 없는 문자가 섞이지 않았는지 확인하세요.", bundle: .module)
    case .url(.notHTTPS):
      String(localized: "https:// 로 시작하는 주소만 등록할 수 있습니다.", bundle: .module)
    case .url(.missingHost):
      String(localized: "https:// 뒤에 서버 주소(예: example.com)를 입력하세요.", bundle: .module)
    case .url(.hasCredentials):
      String(
        localized: "사용자 이름이나 비밀번호가 든 주소는 등록할 수 없습니다. 로그인 없이 받을 수 있는 주소를 입력하세요.",
        bundle: .module
      )
    case .duplicate:
      String(localized: "이미 등록된 카탈로그입니다.", bundle: .module)
    }
  }

  /// 저장된 주소 아래 안내. 쓸 수 있는 주소는 nil.
  static func entryNote(_ status: CatalogURLEntry.Status) -> String? {
    switch status {
    case .usable:
      return nil
    case let .invalid(problem):
      let reason = self.urlProblemReason(problem)
      return String(localized: "쓸 수 없는 주소라 읽지 않습니다: \(reason).", bundle: .module)
    case let .duplicate(firstIndex: index):
      // 화면의 순서는 1부터 센다.
      let order = index + 1
      return String(localized: "위의 \(order)번째 주소와 같은 카탈로그라 한 번만 읽습니다.", bundle: .module)
    }
  }

  /// 주소 검사에 걸린 이유 (마침표 없이). 저장된 주소와 카탈로그의 buildURL 안내가 함께 쓴다.
  static func urlProblemReason(_ problem: DownloadURLProblem) -> String {
    switch problem {
    case .empty:
      String(localized: "빈 주소입니다", bundle: .module)
    case .malformed:
      String(localized: "주소로 읽을 수 없습니다", bundle: .module)
    case .notHTTPS:
      String(localized: "https:// 로 시작하는 주소가 아닙니다", bundle: .module)
    case .missingHost:
      String(localized: "서버 주소(예: example.com)가 없습니다", bundle: .module)
    case .hasCredentials:
      String(localized: "사용자 이름이나 비밀번호가 들어 있습니다", bundle: .module)
    }
  }

  // MARK: - 등록 결과

  static func added(appCount: Int) -> String {
    String(localized: "등록했습니다. 앱 \(appCount)개가 있습니다.", bundle: .module)
  }
}
