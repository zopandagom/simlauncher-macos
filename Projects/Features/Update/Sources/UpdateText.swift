import Core
import Foundation
import UpdateCheckInterface

/// 업데이트 알림 문구. 모두 이 모듈의 `Localizable.xcstrings` 에서 찾는다 (`bundle: .module`).
/// 버전은 숫자 버전으로 해석된 값의 `description`(예 "1.3.0")만 보간한다 (응답 원문 문자열은 보이지 않는다).
enum UpdateText {
  // MARK: - 메뉴·창

  static var menuItem: String {
    String(localized: "업데이트 확인…", bundle: .module)
  }

  static var windowTitle: String {
    String(localized: "업데이트 확인", bundle: .module)
  }

  static var checking: String {
    String(localized: "새 버전을 확인하는 중…", bundle: .module)
  }

  static var checkingCaption: String {
    String(localized: "창을 닫아도 확인은 끝까지 진행되고, 새 버전이면 메인 창 위쪽에 알립니다.", bundle: .module)
  }

  /// 저장소가 없는 빌드의 방어 화면 (입구가 없어 정상 흐름에선 보이지 않는다).
  static var unavailable: String {
    String(localized: "이 빌드에는 업데이트 확인 기능이 없습니다.", bundle: .module)
  }

  static func newerTitle(_ version: AppVersion) -> String {
    String(localized: "새 버전이 나왔습니다: SimLauncher \(version.description)", bundle: .module)
  }

  static func currentLine(_ current: AppVersion) -> String {
    String(localized: "지금 쓰는 버전: \(current.description)", bundle: .module)
  }

  static var skippedNote: String {
    String(localized: "건너뛰기로 한 버전이라 자동 알림에서는 보이지 않습니다.", bundle: .module)
  }

  static func upToDate(_ current: AppVersion) -> String {
    String(localized: "최신 버전을 쓰고 있습니다 (SimLauncher \(current.description)).", bundle: .module)
  }

  static var currentUnknown: String {
    String(
      localized: "이 앱의 버전을 읽지 못해 새 버전인지 비교하지 못했습니다. 다운로드 페이지에서 직접 확인하세요.",
      bundle: .module
    )
  }

  static var latestUnrecognized: String {
    String(
      localized: "최신 릴리스의 버전 형식을 알 수 없어 비교하지 못했습니다. 다운로드 페이지에서 직접 확인하세요.",
      bundle: .module
    )
  }

  static var failedTitle: String {
    String(localized: "업데이트를 확인하지 못했습니다", bundle: .module)
  }

  /// 실패 본문. 403·429(`refused`)는 원인을 단정하지 않고 프록시·방화벽 확인과 잠시 뒤 다시 시도를 안내한다.
  static func message(for error: UpdateCheckError) -> String {
    switch error {
    case .offline:
      String(localized: "인터넷에 연결되어 있지 않습니다. 연결을 확인한 뒤 다시 시도하세요.", bundle: .module)
    case .timedOut:
      String(localized: "GitHub 에서 60초 안에 답을 받지 못했습니다. 연결을 확인한 뒤 다시 시도하세요.", bundle: .module)
    case .connectionFailed:
      String(
        localized: """
        GitHub 에 연결하지 못했습니다. 인터넷 연결을 확인하고, \
        회사 네트워크라면 github.com·githubusercontent.com 접속이 막혀 있지 않은지 확인하세요.
        """,
        bundle: .module
      )
    case .refused:
      String(
        localized: """
        요청이 거절되었습니다. 회사 네트워크라면 프록시·방화벽이 github.com·githubusercontent.com 접속을 \
        막고 있지 않은지 확인하고, 잠시 뒤 다시 시도하세요. 다운로드 페이지에서 직접 확인할 수도 있습니다.
        """,
        bundle: .module
      )
    case .notFound:
      String(localized: "최신 릴리스에서 버전 정보를 찾지 못했습니다. 다운로드 페이지에서 직접 확인하세요.", bundle: .module)
    case let .httpStatus(code):
      String(localized: "GitHub 이 요청을 처리하지 못했습니다 (HTTP \(code)). 잠시 뒤 다시 시도하세요.", bundle: .module)
    case .unexpectedResponse:
      String(localized: "최신 릴리스의 버전 정보를 읽지 못했습니다. 다운로드 페이지에서 직접 확인하세요.", bundle: .module)
    case .failed, .cancelled, .notConfigured:
      // notConfigured 는 입구가 없어 나오지 않는다.
      String(localized: "업데이트를 확인하지 못했습니다. 잠시 뒤 다시 시도하세요.", bundle: .module)
    }
  }

  // MARK: - 버튼

  static var openDownloadPageButton: String {
    String(localized: "다운로드 페이지 열기", bundle: .module)
  }

  static var skipVersionButton: String {
    String(localized: "이 버전 건너뛰기", bundle: .module)
  }

  static var retryButton: String {
    String(localized: "다시 시도", bundle: .module)
  }

  static var closeButton: String {
    String(localized: "닫기", bundle: .module)
  }

  // MARK: - 배너

  static func banner(_ version: AppVersion, current: AppVersion) -> String {
    String(
      localized: "새 버전이 나왔습니다: SimLauncher \(version.description) (지금 \(current.description))",
      bundle: .module
    )
  }

  /// 배너 닫기(×) 버튼의 접근성 라벨·도움말.
  static var dismissBannerLabel: String {
    String(localized: "하루 동안 숨기기", bundle: .module)
  }
}
