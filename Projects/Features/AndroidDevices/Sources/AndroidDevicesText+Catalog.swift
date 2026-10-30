import AndroidPackageInterface
import Core
import DownloadInterface
import Foundation

/// 카탈로그에서 설치 문구 (메뉴 항목·시트·카탈로그 버전의 받기와 받은 파일 실패). 카탈로그 값(주소·앱·버전 이름 등)은 문구에 넣지
/// 않고 View 가 `Text(verbatim:)` 으로 보인다 (버전 캡션의 조각은 예외: 값은 `%@` 인자로만 들어간다). iOS 기기 목록(Launcher)과
/// 같은 문구는 같은 키·값이고 `LauncherTextSyncTests` 가 묶는다. 시트 제목·Android 앱이 없는 구역 안내·받은 apk 실패는 Android
/// 문장이다. 키는 다른 문구와 같은 `Localizable.xcstrings` 에 있다.
extension AndroidDevicesText {
  // MARK: - 기기 행

  static var installFromCatalogMenuItem: String {
    String(localized: "카탈로그에서…", bundle: .module)
  }

  // MARK: - 시트

  static func catalogSheetTitle(for device: AndroidDeviceLabel) -> String {
    let label = self.label(device)
    return String(localized: "\(label) 기기에 카탈로그에서 앱 설치", bundle: .module)
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

  /// 읽은 구역에 보일 Android 앱이 없는 이유. 앱이 전혀 없는 문구는 Launcher 와 같은 키·값이다.
  static func catalogEmptyReason(_ reason: AndroidCatalogEmptyReason) -> String {
    switch reason {
    case .noApps:
      String(localized: "이 카탈로그에는 앱이 없습니다.", bundle: .module)
    case .noAndroidApps:
      String(localized: "이 카탈로그에는 Android 앱이 없습니다.", bundle: .module)
    case .schemaVersion1:
      String(
        localized: """
        이 카탈로그는 schemaVersion 1 이라 iOS 앱만 담습니다. \
        Android 앱을 받으려면 카탈로그를 만든 사람에게 schemaVersion 2 로 바꿔 달라고 알려 주세요.
        """,
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

  /// 구역의 상태 줄 (받기·해석 실패, 쓸 수 없는 주소). 다음 할 일은 값에 담긴 잠김으로 고른다. View 가 부르는 실패 구역 문구 함수는
  /// 이것 하나다.
  static func catalogSourceNote(_ note: AndroidCatalogSourceNote) -> String {
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

// MARK: - 카탈로그 버전 설치 실패

/// 사용자가 고칠 주소가 없으므로 빌드 주소·빌드 파일 쪽 원인은 카탈로그를 만든 사람에게 알리도록 안내한다 (빌드가 없거나 접근이
/// 거부되면 다른 버전 고르기도). 빌드 주소와 관계없는 원인(오프라인·프록시 인증·서버 오류·시간 초과·연결 끊김·디스크·임시 폴더)은
/// URL 에서 설치와 같은 문구다. 받기 실패는 Launcher 의 카탈로그 버전 설치와 같은 키·값이다.
extension AndroidDevicesText {
  /// 카탈로그 버전의 받기 실패.
  static func catalogInstallDownloadMessage(for error: DownloadError) -> String {
    switch error {
    case .insecureRedirect:
      String(
        localized: """
        서버가 https 가 아닌 주소(http 등)로 넘겨 보내 빌드를 받지 않았습니다. \
        이 버전의 빌드를 https 로 바로 받을 수 있게 해 달라고 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    case let .httpStatus(code):
      self.catalogInstallHTTPStatusMessage(code)
    case .hostNotFound:
      String(
        localized: """
        빌드 서버 주소를 찾지 못했습니다. 회사 안의 주소라면 사내망(VPN 등)에 연결되어 있는지 확인하고, \
        계속되면 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    case .cannotConnect:
      String(
        localized: """
        빌드 서버에 연결하지 못했습니다. 회사 안의 주소라면 사내망(VPN 등) 연결과 프록시 설정을 확인하고, \
        계속되면 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    case .secureConnectionFailed:
      String(
        localized: """
        빌드 서버와 보안 연결(TLS)을 맺지 못했습니다(인증서 문제 등). \
        계속되면 서버 관리자나 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    case .offline, .timedOut, .connectionLost, .insufficientDiskSpace, .storageUnavailable:
      self.urlDownloadMessage(for: error)
    case .tooLarge, .failed, .cancelled:
      // `.tooLarge` 는 작은 파일 받기에서만, `.cancelled` 는 취소를 누르지 않았을 때만 알림이 되며 둘 다 나오지 않는다.
      String(localized: "빌드 파일을 받지 못했습니다. 다시 시도하고, 계속되면 카탈로그를 만든 사람에게 알려 주세요.", bundle: .module)
    }
  }

  /// 2xx 가 아닌 HTTP 상태. 407·5xx 는 URL 에서 설치와 같은 문구다.
  private static func catalogInstallHTTPStatusMessage(_ code: Int) -> String {
    switch code {
    case 401, 403:
      // 403 은 권한 없는 저장소(S3 등)의 없는 파일에도 온다. 원인은 둘 다 가능성으로 쓴다.
      String(
        localized: """
        서버가 접근을 거부해 빌드를 받지 못했습니다 (HTTP \(code)). 지워졌거나 로그인이 필요한 빌드일 수 있습니다. \
        다른 버전을 고르거나 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    case 407, 500 ..< 600:
      self.httpStatusMessage(code)
    case 404, 410:
      String(
        localized: """
        서버에 이 버전의 빌드 파일이 없습니다 (HTTP \(code)). 지워진 빌드일 수 있습니다. \
        다른 버전을 고르거나 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    default:
      String(
        localized: "서버가 빌드 파일을 주지 않았습니다 (HTTP \(code)). 다시 시도하고, 계속되면 카탈로그를 만든 사람에게 알려 주세요.",
        bundle: .module
      )
    }
  }

  /// 카탈로그 버전에서 받은 파일의 apk 검사 실패. 서명 없음까지 카탈로그 문맥 문구, 잘못된 경로·임시 폴더는 고른 파일과 같은 문구다.
  static func catalogDownloadedPackageMessage(for error: AndroidPackageError, isWebPage: Bool) -> String {
    switch error {
    case .unreadable where isWebPage:
      String(
        localized: """
        apk 파일 대신 웹 페이지를 받았습니다. 이 버전의 빌드 주소가 로그인이 필요한 주소이거나 내려받기 페이지일 수 있습니다. \
        카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    case .unreadable:
      String(
        localized: "받은 파일이 apk 가 아니거나 손상되었습니다. 다시 시도하고, 계속되면 카탈로그를 만든 사람에게 알려 주세요.",
        bundle: .module
      )
    case .appBundle:
      String(
        localized: """
        이 버전의 빌드는 App Bundle(.aab)이라 기기에 바로 설치할 수 없습니다. \
        .apk 를 올려 달라고 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    case .unsigned:
      String(localized: "이 버전의 apk 는 서명되지 않아 설치할 수 없습니다. 카탈로그를 만든 사람에게 알려 주세요.", bundle: .module)
    case .unsafeEntry, .inspectionUnavailable:
      self.message(for: error)
    case .notLocalFile, .fileNotFound, .notAPK, .splitPackage:
      // 받은 파일은 늘 로컬 `download.apk` 라 나오지 않는다.
      self.downloadedFileUnreadable
    }
  }
}
