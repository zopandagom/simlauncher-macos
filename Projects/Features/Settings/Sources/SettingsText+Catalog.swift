import Core
import DownloadInterface
import Foundation

/// 등록 확인 실패 문구 (카탈로그 받기 실패·형식 문제와 그 위치). 키는 다른 문구와 같은 `Localizable.xcstrings` 에 있다.
extension SettingsText {
  static func message(for failure: CatalogRegistrationFailure) -> String {
    switch failure {
    case let .download(error):
      self.message(for: error)
    case let .catalog(problem):
      self.message(for: problem)
    }
  }

  // MARK: - 받기 실패

  /// 카탈로그 받기 실패의 본문. 케이스마다 원인과 다음 할 일.
  static func message(for error: DownloadError) -> String {
    switch error {
    case .insecureRedirect:
      String(
        localized: """
        서버가 https 가 아닌 주소(http 등)로 넘겨 보내 받지 않았습니다. \
        주소가 맞는지 확인하고, 맞다면 https 로 바로 받을 수 있는지 카탈로그를 만든 사람에게 확인하세요.
        """,
        bundle: .module
      )
    case let .httpStatus(code):
      self.httpStatusMessage(code)
    case .offline, .hostNotFound, .cannotConnect, .timedOut, .connectionLost, .secureConnectionFailed:
      self.connectionMessage(for: error)
    case .tooLarge:
      // 서버가 알린 크기로 받기 전에 막았거나 받다가 멈췄다. 받은 것이 카탈로그라는 보장이 없어 주소 확인부터 안내한다.
      String(
        localized: """
        파일이 5 MiB 를 넘어 받지 않았습니다. 주소가 catalog.json 파일을 바로 가리키는지 확인하고, \
        맞다면 오래된 버전 항목을 지워 달라고 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    case .insufficientDiskSpace, .storageUnavailable, .failed, .cancelled:
      // 카탈로그는 메모리로 받아 파일을 만들지 않으므로 앞 둘은 나오지 않고, `.cancelled` 는 결과로 남기지 않는다.
      self.downloadFailed
    }
  }

  /// 연결·전송 실패의 본문 (`message(for:)` 가 넘기는 케이스만 온다. 복잡도를 나눈다).
  private static func connectionMessage(for error: DownloadError) -> String {
    switch error {
    case .offline:
      String(localized: "인터넷에 연결되어 있지 않습니다. 연결을 확인한 뒤 다시 시도하세요.", bundle: .module)
    case .hostNotFound:
      String(
        localized: "서버 주소를 찾지 못했습니다. 주소의 철자를 확인하고, 회사 안의 주소라면 사내망(VPN 등)에 연결되어 있는지 확인하세요.",
        bundle: .module
      )
    case .cannotConnect:
      String(
        localized: "서버에 연결하지 못했습니다. 주소를 확인하고, 회사 안의 주소라면 사내망(VPN 등) 연결과 프록시 설정을 확인하세요.",
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
        주소가 맞는지 확인하고, 계속되면 서버 관리자에게 알려 주세요.
        """,
        bundle: .module
      )
    case .insecureRedirect, .httpStatus, .insufficientDiskSpace, .storageUnavailable, .tooLarge, .failed, .cancelled:
      self.downloadFailed
    }
  }

  private static var downloadFailed: String {
    String(localized: "카탈로그를 받지 못했습니다. 주소를 확인한 뒤 다시 시도하세요.", bundle: .module)
  }

  /// 2xx 가 아닌 HTTP 상태.
  static func httpStatusMessage(_ code: Int) -> String {
    switch code {
    case 401, 403:
      // 403 은 로그인 요구만이 아니다: 목록 권한이 없는 저장소(S3 등)는 없는 파일에도 403 을 준다.
      String(
        localized: "서버가 접근을 거부해 받지 못했습니다 (HTTP \(code)). 주소가 맞는지, 로그인 없이 받을 수 있는 주소인지 확인하세요.",
        bundle: .module
      )
    case 404, 410:
      String(
        localized: "서버에 카탈로그 파일이 없습니다 (HTTP \(code)). 주소가 맞는지 확인하세요.",
        bundle: .module
      )
    case 500 ..< 600:
      String(localized: "서버 오류로 받지 못했습니다 (HTTP \(code)). 잠시 뒤 다시 시도하세요.", bundle: .module)
    default:
      String(localized: "서버가 파일을 주지 않았습니다 (HTTP \(code)). 주소를 확인한 뒤 다시 시도하세요.", bundle: .module)
    }
  }

  // MARK: - 형식 문제

  /// 형식 문제의 본문: 첫 줄 "등록하지 않았습니다" + 무엇이 어디서 틀렸는지 + (카탈로그를 고칠 문제면) 누구에게 알릴지.
  static func message(for problem: BuildCatalogProblem) -> String {
    let header = String(localized: "카탈로그 형식이 맞지 않아 등록하지 않았습니다.", bundle: .module)
    let detail = self.detail(for: problem)
    switch problem {
    case .notJSONObject:
      // 주소가 틀린 경우가 많아 주소 확인을 먼저 안내하고, 만든 사람에게 알리는 안내는 본문 끝에 있다.
      return [header, detail].joined(separator: "\n")
    case let .unsupportedSchemaVersion(version) where version > BuildCatalog.latestSchemaVersion:
      // 앱을 업데이트할 일이라 카탈로그를 만든 사람에게 알릴 필요가 없다.
      return [header, detail].joined(separator: "\n")
    case let .missingField(_, position) where position == .root, let .wrongType(_, position) where position == .root:
      // 카탈로그가 아닌 다른 JSON 객체(API 응답 등)를 가리키는 주소도 맨 먼저 최상위 필드에서 걸린다.
      return [header, detail, self.checkAddressThenReport].joined(separator: "\n")
    default:
      return [header, detail, self.reportToAuthor].joined(separator: "\n")
    }
  }

  private static var reportToAuthor: String {
    String(localized: "카탈로그를 만든 사람에게 알려 주세요.", bundle: .module)
  }

  private static var checkAddressThenReport: String {
    String(
      localized: "주소가 catalog.json 파일을 바로 가리키는지 확인하고, 맞다면 카탈로그를 만든 사람에게 알려 주세요.",
      bundle: .module
    )
  }

  /// 무엇이 어디서 틀렸는지. 필드 문제는 `fieldDetail` 로 나눈다 (복잡도).
  private static func detail(for problem: BuildCatalogProblem) -> String {
    switch problem {
    case .notJSONObject:
      String(
        localized: """
        받은 파일을 카탈로그(JSON 객체)로 읽지 못했습니다. 로그인 페이지 같은 웹 페이지이거나 다른 파일일 수 있습니다. \
        주소가 catalog.json 파일을 바로 가리키는지 확인하고, 맞다면 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    case let .unsupportedSchemaVersion(version):
      self.schemaVersionDetail(version)
    case .missingField, .wrongType, .emptyField:
      self.fieldDetail(for: problem)
    case let .invalidID(position):
      self.invalidIDDetail(at: self.location(position))
    case let .unsupportedPlatform(position):
      self.unsupportedPlatformDetail(at: self.location(position))
    case let .duplicateAppID(position):
      self.duplicateAppIDDetail(at: self.location(position))
    case let .duplicateVersionID(position):
      self.duplicateVersionIDDetail(at: self.location(position))
    case let .invalidCreatedAt(position):
      self.invalidCreatedAtDetail(at: self.location(position))
    case let .invalidBuildURL(urlProblem, position):
      self.invalidBuildURLDetail(at: self.location(position), reason: self.urlProblemReason(urlProblem))
    }
  }

  private static func schemaVersionDetail(_ version: Int) -> String {
    if version > BuildCatalog.latestSchemaVersion {
      return String(
        localized: "이 카탈로그는 이 앱보다 새 규격(schemaVersion \(version))입니다. SimLauncher 를 업데이트한 뒤 다시 등록하세요.",
        bundle: .module
      )
    }
    let latest = BuildCatalog.latestSchemaVersion
    return String(localized: "카탈로그의 schemaVersion \(version) 은 없는 규격입니다 (지원: 1~\(latest)).", bundle: .module)
  }

  /// 필드 문제 (`detail(for:)` 가 넘기는 케이스만 온다). 필드 이름은 JSON 키 그대로다.
  private static func fieldDetail(for problem: BuildCatalogProblem) -> String {
    switch problem {
    case let .missingField(field, position):
      let place = self.location(position)
      let name = field.rawValue
      return String(localized: "\(place)에 필수 필드 \(name) 가 없거나 null 입니다.", bundle: .module)
    case let .wrongType(field, position):
      // `apps`·`versions` 배열의 항목이 객체가 아니면 그 배열 필드와 항목 위치로 온다.
      let isItem = (field == .apps && position.appIndex != nil) || (field == .versions && position.versionIndex != nil)
      if isItem {
        return self.notObjectItemDetail(at: self.location(position), field: field)
      }
      let place = self.location(position)
      let name = field.rawValue
      return String(localized: "\(place)의 \(name) 값의 형식(타입)이 다릅니다.", bundle: .module)
    case let .emptyField(field, position):
      let place = self.location(position)
      let name = field.rawValue
      return String(localized: "\(place)의 \(name) 가 비어 있습니다.", bundle: .module)
    case .notJSONObject, .unsupportedSchemaVersion, .invalidID, .unsupportedPlatform, .duplicateAppID,
         .duplicateVersionID, .invalidCreatedAt, .invalidBuildURL:
      return self.detail(for: problem)
    }
  }

  private static func notObjectItemDetail(at place: String, field: BuildCatalogProblem.Field) -> String {
    let name = field.rawValue
    return String(localized: "\(place)이 객체가 아닙니다 (\(name) 배열의 항목은 객체여야 합니다).", bundle: .module)
  }

  private static func invalidIDDetail(at place: String) -> String {
    String(
      localized: "\(place)의 id 가 형식에 맞지 않습니다 (영문·숫자로 시작하고 영문·숫자·. _ - 만, 128자까지).",
      bundle: .module
    )
  }

  private static func unsupportedPlatformDetail(at place: String) -> String {
    String(localized: "\(place)의 platform 이 ios 나 android 가 아닙니다 (소문자로 씁니다).", bundle: .module)
  }

  private static func duplicateAppIDDetail(at place: String) -> String {
    String(localized: "\(place)의 id 가 앞의 앱과 같습니다 (대소문자 무시).", bundle: .module)
  }

  private static func duplicateVersionIDDetail(at place: String) -> String {
    String(localized: "\(place)의 id 가 같은 앱의 앞 버전과 같습니다 (대소문자 무시).", bundle: .module)
  }

  private static func invalidCreatedAtDetail(at place: String) -> String {
    String(localized: "\(place)의 createdAt 이 날짜 형식(예: 2026-10-21T04:08:49Z)이 아니거나 없는 날짜·시각입니다.", bundle: .module)
  }

  private static func invalidBuildURLDetail(at place: String, reason: String) -> String {
    String(localized: "\(place)의 buildURL 을 쓸 수 없습니다: \(reason).", bundle: .module)
  }

  // MARK: - 위치

  /// 문제가 난 곳. 인덱스는 1부터 센다. id 는 형식 검사를 통과했을 때만 괄호로 붙는다.
  static func location(_ position: BuildCatalogProblem.Position) -> String {
    guard let appIndex = position.appIndex else {
      return String(localized: "카탈로그 최상위", bundle: .module)
    }
    let appPart = self.appLocation(order: appIndex + 1, id: position.appID)
    guard let versionIndex = position.versionIndex else {
      return appPart
    }
    let versionPart = self.versionLocation(order: versionIndex + 1, id: position.versionID)
    return String(localized: "\(appPart)의 \(versionPart)", bundle: .module)
  }

  private static func appLocation(order: Int, id: String?) -> String {
    guard let id else {
      return String(localized: "\(order)번째 앱", bundle: .module)
    }
    return String(localized: "\(order)번째 앱(id: \(id))", bundle: .module)
  }

  private static func versionLocation(order: Int, id: String?) -> String {
    guard let id else {
      return String(localized: "\(order)번째 버전", bundle: .module)
    }
    return String(localized: "\(order)번째 버전(id: \(id))", bundle: .module)
  }
}
