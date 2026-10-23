import Core
import DownloadInterface
import Foundation

/// 카탈로그에서 설치 시트의 카탈로그 읽기 실패 문구 (받기 실패·형식 문제와 그 위치). 주소 확인을 안내하는 문구는 고칠 곳을
/// "설정(⌘,)" 으로 적는다 (등록해 둔 주소라 시트에서는 고칠 수 없다). 관리자가 잠근 목록이면 사용자가 주소를 바꿀 수 없으므로
/// 그 부분만 "Mac 을 관리하는 담당자" 에게 확인해 달라는 안내로 바꾼다(`isLocked`). 주소와 관계없는 다음 할 일은 잠김과 관계없이 같다.
/// 문맥 없는 조각(위치·필드 설명·주소 이유·60초·연결 끊김)은 Settings 와 같은 키·값이고, `CatalogFragmentSyncTests` 가
/// Settings 원본과 같은지 확인한다. 키는 다른 문구와 같은 `Localizable.xcstrings` 에 있다.
extension LauncherText {
  /// 잠김에 기본값을 두지 않는다 (부르는 곳이 잠김을 빠뜨리면 컴파일러가 잡는다).
  static func catalogLoadMessage(for failure: CatalogLoadFailure, isLocked: Bool) -> String {
    if isLocked, let locked = self.lockedCatalogLoadMessage(for: failure) {
      return locked
    }
    return switch failure {
    case let .download(error):
      self.catalogDownloadMessage(for: error)
    case let .catalog(problem):
      self.catalogProblemMessage(for: problem)
    }
  }

  // MARK: - 받기 실패

  /// 카탈로그 받기 실패의 본문. 케이스마다 원인과 다음 할 일.
  private static func catalogDownloadMessage(for error: DownloadError) -> String {
    switch error {
    case .insecureRedirect:
      String(
        localized: """
        서버가 https 가 아닌 주소(http 등)로 넘겨 보내 받지 않았습니다. \
        https 로 바로 받을 수 있는지 카탈로그를 만든 사람에게 확인하세요.
        """,
        bundle: .module
      )
    case let .httpStatus(code):
      self.catalogHTTPStatusMessage(code)
    case .offline, .hostNotFound, .cannotConnect, .timedOut, .connectionLost, .secureConnectionFailed:
      self.catalogConnectionMessage(for: error)
    case .tooLarge:
      String(
        localized: """
        파일이 5 MiB 를 넘어 받지 않았습니다. 설정(⌘,)에서 주소가 catalog.json 파일을 바로 가리키는지 확인하고, \
        맞다면 오래된 버전 항목을 지워 달라고 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    case .insufficientDiskSpace, .storageUnavailable, .failed, .cancelled:
      // 카탈로그는 메모리로 받아 앞 둘은 나오지 않는다. `.cancelled` 는 지금 받기에서 나오지 않지만, 와도 "읽는 중" 에
      // 갇히지 않게 실패로 보인다.
      self.catalogDownloadFailed
    }
  }

  /// 연결·전송 실패의 본문 (`catalogDownloadMessage(for:)` 가 넘기는 케이스만 온다. 복잡도를 나눈다).
  private static func catalogConnectionMessage(for error: DownloadError) -> String {
    switch error {
    case .offline:
      // URL 설치와 같은 문구.
      self.message(for: error)
    case .hostNotFound:
      String(
        localized: """
        서버 주소를 찾지 못했습니다. 회사 안의 주소라면 사내망(VPN 등)에 연결되어 있는지 확인하고, \
        아니면 설정(⌘,)에서 주소의 철자를 확인하세요.
        """,
        bundle: .module
      )
    case .cannotConnect:
      String(
        localized: """
        서버에 연결하지 못했습니다. 회사 안의 주소라면 사내망(VPN 등) 연결과 프록시 설정을 확인하고, \
        아니면 설정(⌘,)에서 주소를 확인하세요.
        """,
        bundle: .module
      )
    case .timedOut:
      // `fetchData` 는 응답이 없을 때뿐 아니라 받는 중이어도 전체 60초를 넘기면 멈춘다.
      String(localized: "카탈로그를 60초 안에 받지 못해 멈췄습니다. 연결을 확인한 뒤 다시 시도하세요.", bundle: .module)
    case .connectionLost:
      String(localized: "받는 중 연결이 끊겼습니다. 다시 시도하세요.", bundle: .module)
    case .secureConnectionFailed:
      String(
        localized: """
        서버와 보안 연결(TLS)을 맺지 못했습니다(인증서 문제 등). \
        설정(⌘,)에서 주소가 맞는지 확인하고, 계속되면 서버 관리자에게 알려 주세요.
        """,
        bundle: .module
      )
    case .insecureRedirect, .httpStatus, .insufficientDiskSpace, .storageUnavailable, .tooLarge, .failed, .cancelled:
      self.catalogDownloadFailed
    }
  }

  private static var catalogDownloadFailed: String {
    String(localized: "카탈로그를 받지 못했습니다. 다시 시도하고, 계속되면 설정(⌘,)에서 주소를 확인하세요.", bundle: .module)
  }

  /// 2xx 가 아닌 HTTP 상태. 407·5xx 는 URL 설치와 같은 문구다.
  private static func catalogHTTPStatusMessage(_ code: Int) -> String {
    switch code {
    case 401, 403:
      // 403 은 로그인 요구만이 아니다: 목록 권한이 없는 저장소(S3 등)는 없는 파일에도 403 을 준다. 주소 확인이 먼저다.
      String(
        localized: """
        서버가 접근을 거부해 받지 못했습니다 (HTTP \(code)). 설정(⌘,)에서 주소가 맞는지 확인하고, \
        맞다면 로그인 없이 받을 수 있는 주소인지 카탈로그를 만든 사람에게 확인하세요.
        """,
        bundle: .module
      )
    case 407, 500 ..< 600:
      self.httpStatusMessage(code)
    case 404, 410:
      // 등록한 뒤 파일이 옮겨졌을 수 있어 만든 사람에게 알리는 안내를 더한다.
      String(
        localized: """
        서버에 카탈로그 파일이 없습니다 (HTTP \(code)). 설정(⌘,)에서 주소가 맞는지 확인하고, \
        맞다면 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    default:
      String(
        localized: "서버가 카탈로그를 주지 않았습니다 (HTTP \(code)). 설정(⌘,)에서 주소를 확인한 뒤 다시 시도하세요.",
        bundle: .module
      )
    }
  }

  // MARK: - 형식 문제

  /// 형식 문제의 본문: 첫 줄 "읽지 않았습니다" + 무엇이 어디서 틀렸는지 + 다음 할 일 (새 규격은 내용 문장 안에 있다).
  private static func catalogProblemMessage(for problem: BuildCatalogProblem) -> String {
    let header = String(localized: "카탈로그 형식이 맞지 않아 읽지 않았습니다.", bundle: .module)
    let detail = self.catalogDetail(for: problem)
    switch problem {
    case .notJSONObject:
      return [header, detail, self.checkCatalogAddressThenReport].joined(separator: "\n")
    case let .unsupportedSchemaVersion(version) where version > BuildCatalog.supportedSchemaVersion:
      // 앱을 업데이트할 일이라 카탈로그를 만든 사람에게 알릴 필요가 없다.
      return [header, detail].joined(separator: "\n")
    case let .missingField(_, position) where position == .root, let .wrongType(_, position) where position == .root:
      // 카탈로그가 아닌 다른 JSON 객체(API 응답 등)를 가리키는 주소도 맨 먼저 최상위 필드에서 걸린다.
      return [header, detail, self.checkCatalogAddressThenReport].joined(separator: "\n")
    default:
      return [header, detail, self.reportToCatalogAuthor].joined(separator: "\n")
    }
  }

  private static var reportToCatalogAuthor: String {
    String(localized: "카탈로그를 만든 사람에게 알려 주세요.", bundle: .module)
  }

  private static var checkCatalogAddressThenReport: String {
    String(
      localized: "설정(⌘,)에서 주소가 catalog.json 파일을 바로 가리키는지 확인하고, 맞다면 카탈로그를 만든 사람에게 알려 주세요.",
      bundle: .module
    )
  }

  /// 무엇이 어디서 틀렸는지. 필드 문제는 `catalogFieldDetail` 로 나눈다 (복잡도).
  private static func catalogDetail(for problem: BuildCatalogProblem) -> String {
    switch problem {
    case .notJSONObject:
      String(
        localized: "받은 파일을 카탈로그(JSON 객체)로 읽지 못했습니다. 로그인 페이지 같은 웹 페이지이거나 다른 파일일 수 있습니다.",
        bundle: .module
      )
    case let .unsupportedSchemaVersion(version):
      self.catalogSchemaVersionDetail(version)
    case .missingField, .wrongType, .emptyField:
      self.catalogFieldDetail(for: problem)
    case let .invalidID(position):
      self.catalogInvalidIDDetail(at: self.catalogLocation(position))
    case let .duplicateAppID(position):
      self.catalogDuplicateAppIDDetail(at: self.catalogLocation(position))
    case let .duplicateVersionID(position):
      self.catalogDuplicateVersionIDDetail(at: self.catalogLocation(position))
    case let .invalidCreatedAt(position):
      self.catalogInvalidCreatedAtDetail(at: self.catalogLocation(position))
    case let .invalidBuildURL(urlProblem, position):
      self.catalogInvalidBuildURLDetail(
        at: self.catalogLocation(position),
        reason: self.catalogURLProblemReason(urlProblem)
      )
    }
  }

  private static func catalogSchemaVersionDetail(_ version: Int) -> String {
    if version > BuildCatalog.supportedSchemaVersion {
      return String(
        localized: "이 카탈로그는 이 앱보다 새 규격(schemaVersion \(version))입니다. SimLauncher 를 업데이트하세요.",
        bundle: .module
      )
    }
    let supported = BuildCatalog.supportedSchemaVersion
    return String(localized: "카탈로그의 schemaVersion \(version) 은 없는 규격입니다 (지원: \(supported)).", bundle: .module)
  }

  /// 필드 문제 (`catalogDetail(for:)` 가 넘기는 케이스만 온다). 필드 이름은 JSON 키 그대로다.
  private static func catalogFieldDetail(for problem: BuildCatalogProblem) -> String {
    switch problem {
    case let .missingField(field, position):
      let place = self.catalogLocation(position)
      let name = field.rawValue
      return String(localized: "\(place)에 필수 필드 \(name) 가 없거나 null 입니다.", bundle: .module)
    case let .wrongType(field, position):
      // `apps`·`versions` 배열의 항목이 객체가 아니면 그 배열 필드와 항목 위치로 온다.
      let isItem = (field == .apps && position.appIndex != nil) || (field == .versions && position.versionIndex != nil)
      if isItem {
        return self.catalogNotObjectItemDetail(at: self.catalogLocation(position), field: field)
      }
      let place = self.catalogLocation(position)
      let name = field.rawValue
      return String(localized: "\(place)의 \(name) 값의 형식(타입)이 다릅니다.", bundle: .module)
    case let .emptyField(field, position):
      let place = self.catalogLocation(position)
      let name = field.rawValue
      return String(localized: "\(place)의 \(name) 가 비어 있습니다.", bundle: .module)
    case .notJSONObject, .unsupportedSchemaVersion, .invalidID, .duplicateAppID, .duplicateVersionID,
         .invalidCreatedAt, .invalidBuildURL:
      return self.catalogDetail(for: problem)
    }
  }

  private static func catalogNotObjectItemDetail(at place: String, field: BuildCatalogProblem.Field) -> String {
    let name = field.rawValue
    return String(localized: "\(place)이 객체가 아닙니다 (\(name) 배열의 항목은 객체여야 합니다).", bundle: .module)
  }

  private static func catalogInvalidIDDetail(at place: String) -> String {
    String(
      localized: "\(place)의 id 가 형식에 맞지 않습니다 (영문·숫자로 시작하고 영문·숫자·. _ - 만, 128자까지).",
      bundle: .module
    )
  }

  private static func catalogDuplicateAppIDDetail(at place: String) -> String {
    String(localized: "\(place)의 id 가 앞의 앱과 같습니다 (대소문자 무시).", bundle: .module)
  }

  private static func catalogDuplicateVersionIDDetail(at place: String) -> String {
    String(localized: "\(place)의 id 가 같은 앱의 앞 버전과 같습니다 (대소문자 무시).", bundle: .module)
  }

  private static func catalogInvalidCreatedAtDetail(at place: String) -> String {
    String(localized: "\(place)의 createdAt 이 날짜 형식(예: 2026-10-21T04:08:49Z)이 아니거나 없는 날짜·시각입니다.", bundle: .module)
  }

  private static func catalogInvalidBuildURLDetail(at place: String, reason: String) -> String {
    String(localized: "\(place)의 buildURL 을 쓸 수 없습니다: \(reason).", bundle: .module)
  }

  // MARK: - 위치·주소 이유

  /// 문제가 난 곳. 인덱스는 1부터 센다. id 는 형식 검사를 통과했을 때만 괄호로 붙는다.
  static func catalogLocation(_ position: BuildCatalogProblem.Position) -> String {
    guard let appIndex = position.appIndex else {
      return String(localized: "카탈로그 최상위", bundle: .module)
    }
    let appPart = self.catalogAppLocation(order: appIndex + 1, id: position.appID)
    guard let versionIndex = position.versionIndex else {
      return appPart
    }
    let versionPart = self.catalogVersionLocation(order: versionIndex + 1, id: position.versionID)
    return String(localized: "\(appPart)의 \(versionPart)", bundle: .module)
  }

  private static func catalogAppLocation(order: Int, id: String?) -> String {
    guard let id else {
      return String(localized: "\(order)번째 앱", bundle: .module)
    }
    return String(localized: "\(order)번째 앱(id: \(id))", bundle: .module)
  }

  private static func catalogVersionLocation(order: Int, id: String?) -> String {
    guard let id else {
      return String(localized: "\(order)번째 버전", bundle: .module)
    }
    return String(localized: "\(order)번째 버전(id: \(id))", bundle: .module)
  }

  /// 주소 검사에 걸린 이유 (마침표 없이). 쓸 수 없는 주소 구역과 카탈로그의 buildURL 안내가 함께 쓴다.
  static func catalogURLProblemReason(_ problem: DownloadURLProblem) -> String {
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
}

// MARK: - 잠긴 목록

extension LauncherText {
  /// 잠긴 목록의 카탈로그 읽기 실패. 주소 확인을 안내하는 분기만 담당자 안내 문구이고, 나머지는 nil(잠기지 않은 문구와 같다).
  private static func lockedCatalogLoadMessage(for failure: CatalogLoadFailure) -> String? {
    switch failure {
    case let .download(error):
      self.lockedCatalogDownloadMessage(for: error)
    case let .catalog(problem):
      self.lockedCatalogProblemMessage(for: problem)
    }
  }

  /// 받기 실패 중 주소 확인을 안내하는 분기의 잠김 판. 다시 시도가 있는 문구는 담당자에게 묻기 전에 다시 시도를 먼저 둔다.
  private static func lockedCatalogDownloadMessage(for error: DownloadError) -> String? {
    switch error {
    case let .httpStatus(code):
      self.lockedCatalogHTTPStatusMessage(code)
    case .hostNotFound:
      String(
        localized: """
        서버 주소를 찾지 못했습니다. 회사 안의 주소라면 사내망(VPN 등)에 연결되어 있는지 확인하고, \
        아니면 Mac 을 관리하는 담당자에게 주소의 철자를 확인해 달라고 하세요.
        """,
        bundle: .module
      )
    case .cannotConnect:
      String(
        localized: """
        서버에 연결하지 못했습니다. 회사 안의 주소라면 사내망(VPN 등) 연결과 프록시 설정을 확인하고, \
        아니면 Mac 을 관리하는 담당자에게 주소를 확인해 달라고 하세요.
        """,
        bundle: .module
      )
    case .secureConnectionFailed:
      String(
        localized: """
        서버와 보안 연결(TLS)을 맺지 못했습니다(인증서 문제 등). \
        Mac 을 관리하는 담당자에게 주소가 맞는지 확인해 달라고 하고, 계속되면 서버 관리자에게 알려 주세요.
        """,
        bundle: .module
      )
    case .tooLarge:
      String(
        localized: """
        파일이 5 MiB 를 넘어 받지 않았습니다. Mac 을 관리하는 담당자에게 주소가 catalog.json 파일을 바로 가리키는지 \
        확인해 달라고 하고, 맞다면 오래된 버전 항목을 지워 달라고 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    case .insufficientDiskSpace, .storageUnavailable, .failed, .cancelled:
      String(
        localized: "카탈로그를 받지 못했습니다. 다시 시도하고, 계속되면 Mac 을 관리하는 담당자에게 주소를 확인해 달라고 하세요.",
        bundle: .module
      )
    case .insecureRedirect, .offline, .timedOut, .connectionLost:
      nil
    }
  }

  /// 2xx 가 아닌 HTTP 상태의 잠김 판. 407·5xx 는 주소와 관계없어 nil.
  private static func lockedCatalogHTTPStatusMessage(_ code: Int) -> String? {
    switch code {
    case 401, 403:
      String(
        localized: """
        서버가 접근을 거부해 받지 못했습니다 (HTTP \(code)). Mac 을 관리하는 담당자에게 주소가 맞는지 확인해 달라고 하고, \
        맞다면 로그인 없이 받을 수 있는 주소인지 카탈로그를 만든 사람에게 확인하세요.
        """,
        bundle: .module
      )
    case 407, 500 ..< 600:
      nil
    case 404, 410:
      String(
        localized: """
        서버에 카탈로그 파일이 없습니다 (HTTP \(code)). Mac 을 관리하는 담당자에게 주소가 맞는지 확인해 달라고 하고, \
        맞다면 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    default:
      String(
        localized: """
        서버가 카탈로그를 주지 않았습니다 (HTTP \(code)). \
        다시 시도하고, 계속되면 Mac 을 관리하는 담당자에게 주소를 확인해 달라고 하세요.
        """,
        bundle: .module
      )
    }
  }

  /// 형식 문제 중 주소 확인을 안내하는 것(JSON 객체가 아님, 최상위 필드 문제)의 잠김 판. 나머지는 nil.
  private static func lockedCatalogProblemMessage(for problem: BuildCatalogProblem) -> String? {
    switch problem {
    case .notJSONObject:
      self.lockedCatalogProblemLines(for: problem)
    case let .missingField(_, position) where position == .root, let .wrongType(_, position) where position == .root:
      self.lockedCatalogProblemLines(for: problem)
    case .unsupportedSchemaVersion, .missingField, .wrongType, .emptyField, .invalidID, .duplicateAppID,
         .duplicateVersionID, .invalidCreatedAt, .invalidBuildURL:
      nil
    }
  }

  private static func lockedCatalogProblemLines(for problem: BuildCatalogProblem) -> String {
    let header = String(localized: "카탈로그 형식이 맞지 않아 읽지 않았습니다.", bundle: .module)
    let next = String(
      localized: """
      Mac 을 관리하는 담당자에게 주소가 catalog.json 파일을 바로 가리키는지 확인해 달라고 하고, \
      맞다면 카탈로그를 만든 사람에게 알려 주세요.
      """,
      bundle: .module
    )
    return [header, self.catalogDetail(for: problem), next].joined(separator: "\n")
  }
}
