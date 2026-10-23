import Core
import Foundation

/// 카탈로그에서 설치 문구 (메뉴 항목·시트). 카탈로그 값(주소·앱·버전 이름 등)은 문구에 넣지 않고 View 가 `Text(verbatim:)` 으로
/// 보인다 (버전 캡션의 조각은 예외: 값은 `%@` 인자로만 들어간다). 키는 다른 문구와 같은 `Localizable.xcstrings` 에 있다.
extension LauncherText {
  // MARK: - 기기 행

  static var installFromCatalogMenuItem: String {
    String(localized: "카탈로그에서…", bundle: .module)
  }

  // MARK: - 시트

  static func catalogSheetTitle(for device: LauncherNotice.Device) -> String {
    String(localized: "“\(device.name)” (\(device.runtimeName)) 기기에 카탈로그에서 앱 설치", bundle: .module)
  }

  static var catalogAppsHeader: String {
    String(localized: "앱", bundle: .module)
  }

  static var catalogVersionsHeader: String {
    String(localized: "버전", bundle: .module)
  }

  /// 구역의 읽는 중 줄, 그리고 고른 앱의 카탈로그를 다시 읽는 중일 때 오른쪽 버전 칸.
  static var catalogLoading: String {
    String(localized: "카탈로그를 읽는 중…", bundle: .module)
  }

  static var catalogNoApps: String {
    String(localized: "이 카탈로그에는 앱이 없습니다.", bundle: .module)
  }

  static var catalogNoVersions: String {
    String(localized: "이 앱에는 버전이 없습니다.", bundle: .module)
  }

  static var catalogNoSelection: String {
    String(localized: "왼쪽에서 앱을 고르세요.", bundle: .module)
  }

  static var openSettingsButton: String {
    String(localized: "설정 열기", bundle: .module)
  }

  static var emptyCatalogTitle: String {
    String(localized: "등록된 카탈로그가 없습니다", bundle: .module)
  }

  /// 빈 목록 안내. 잠겼으면 설정에서 등록할 수 없으므로 담당자 문의를 안내한다.
  static func emptyCatalogMessage(isLocked: Bool) -> String {
    if isLocked {
      String(localized: "관리자가 정한 카탈로그 목록이 비어 있습니다. Mac 을 관리하는 담당자에게 문의하세요.", bundle: .module)
    } else {
      String(
        localized: "설정(⌘,)의 “빌드 카탈로그” 에 catalog.json 주소를 등록한 뒤 새로 고침을 누르세요.",
        bundle: .module
      )
    }
  }

  /// 쓸 수 없는 주소 구역. 잠겼으면 지울 수 없으므로 담당자에게 알리게 한다.
  static func invalidCatalogURL(_ problem: DownloadURLProblem, isLocked: Bool) -> String {
    let reason = self.catalogURLProblemReason(problem)
    if isLocked {
      return String(localized: "쓸 수 없는 주소라 읽지 않았습니다: \(reason). Mac 을 관리하는 담당자에게 알려 주세요.", bundle: .module)
    }
    return String(
      localized: "쓸 수 없는 주소라 읽지 않았습니다: \(reason). 설정(⌘,)에서 지우고 https 주소로 다시 등록하세요.",
      bundle: .module
    )
  }

  /// 구역의 상태 줄 (받기·해석 실패, 쓸 수 없는 주소). 다음 할 일은 값에 담긴 잠김으로 고른다. View 가 부르는 구역 문구 함수는
  /// 이것 하나다.
  static func catalogSourceNote(_ note: CatalogSourceNote) -> String {
    switch note {
    case let .failed(failure, isLocked):
      self.catalogLoadMessage(for: failure, isLocked: isLocked)
    case let .invalid(problem, isLocked):
      self.invalidCatalogURL(problem, isLocked: isLocked)
    }
  }

  /// 버전 줄의 캡션: 태그 · 브랜치 · 빌드 번호 · 생성 시각 (있는 것만). 날짜는 Foundation 서식이다.
  static func versionDetail(
    _ version: BuildCatalog.Version,
    locale: Locale = .current,
    timeZone: TimeZone = .current
  ) -> String {
    var parts: [String] = []
    if let tag = version.tag {
      parts.append(String(localized: "태그 \(tag)", bundle: .module))
    }
    if let branch = version.branch {
      parts.append(String(localized: "브랜치 \(branch)", bundle: .module))
    }
    if let buildNumber = version.buildNumber {
      parts.append(String(localized: "빌드 \(buildNumber)", bundle: .module))
    }
    let style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone)
    parts.append(version.createdAt.formatted(style))
    return parts.joined(separator: " · ")
  }
}
