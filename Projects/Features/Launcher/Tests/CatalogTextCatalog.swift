import AppBundleInterface
import Core
import DownloadInterface
import Foundation
@testable import LauncherFeature

/// 카탈로그에서 설치 문구(`LauncherText+Catalog.swift`·`LauncherText+CatalogLoad.swift`·`LauncherText+CatalogInstall.swift`)의
/// String Catalog 키. 확인 한 줄마다 키, 표의 값으로 만든 기대 문구(보간 키는 인자를
/// 넣은 값), 같은 인자로 부른 Launcher 문구 함수의 결과를 담는다. `LauncherResourcesTests` 는 Launcher 표로 모든 키를,
/// `CatalogFragmentSyncTests` 는 Settings 원본 표로 조각을 본다. 표를 인자로 받아 두 표에 같은 확인을 쓴다.
enum CatalogTextCatalog {
  struct Check {
    let key: String
    let expected: String
    let actual: String
  }

  static let device = LauncherNotice.Device(name: "iPhone 17", runtimeName: "iOS 26.0")

  /// Settings 와 같은 키·값으로 둔 문맥 없는 조각 (25개). `fragmentChecks` 의 키와 같은 순서다.
  static let fragmentKeys: [String] = [
    "카탈로그 최상위", "%lld번째 앱", "%lld번째 앱(id: %@)", "%lld번째 버전", "%lld번째 버전(id: %@)", "%@의 %@",
    "%@에 필수 필드 %@ 가 없거나 null 입니다.", "%@의 %@ 값의 형식(타입)이 다릅니다.", "%@의 %@ 가 비어 있습니다.",
    "%@이 객체가 아닙니다 (%@ 배열의 항목은 객체여야 합니다).",
    "%@의 id 가 형식에 맞지 않습니다 (영문·숫자로 시작하고 영문·숫자·. _ - 만, 128자까지).",
    "%@의 platform 이 ios 나 android 가 아닙니다 (소문자로 씁니다).",
    "%@의 id 가 앞의 앱과 같습니다 (대소문자 무시).", "%@의 id 가 같은 앱의 앞 버전과 같습니다 (대소문자 무시).",
    "%@의 createdAt 이 날짜 형식(예: 2026-10-21T04:08:49Z)이 아니거나 없는 날짜·시각입니다.",
    "%@의 buildURL 을 쓸 수 없습니다: %@.", "카탈로그의 schemaVersion %lld 은 없는 규격입니다 (지원: 1~%lld).",
    "카탈로그를 만든 사람에게 알려 주세요.", "빈 주소입니다", "주소로 읽을 수 없습니다", "https:// 로 시작하는 주소가 아닙니다",
    "서버 주소(예: example.com)가 없습니다", "사용자 이름이나 비밀번호가 들어 있습니다",
    "카탈로그를 60초 안에 받지 못해 멈췄습니다. 연결을 확인한 뒤 다시 시도하세요.", "받는 중 연결이 끊겼습니다. 다시 시도하세요.",
  ]

  static let urlProblems: [DownloadURLProblem] = [.empty, .malformed, .notHTTPS, .missingHost, .hasCredentials]

  /// 조각 25개 (Settings 와 같다).
  static func fragmentChecks(_ table: [String: String]) -> [Check] {
    var checks = self.locationChecks(table)
    checks += self.problemChecks(table)
    checks += self.laterProblemChecks(table)
    checks += self.reasonChecks(table)
    return checks
  }

  /// 조각이 아닌 새 키 53개 (보간 없음 37, 보간 16. 잠긴 목록의 카탈로그 읽기 실패 9개 포함).
  static func checks(_ table: [String: String]) -> [Check] {
    var checks = self.sheetChecks(table)
    checks += self.sheetFormatChecks(table)
    checks += self.loadChecks(table)
    checks += self.loadStatusChecks(table)
    checks += self.installChecks(table)
    checks += self.installStatusChecks(table)
    checks += self.lockedLoadChecks(table)
    return checks
  }
}

// MARK: - 도움 함수

extension CatalogTextCatalog {
  /// `table[key]` 에 인자를 넣은 값. 키가 표에 없으면 빈 서식이라 기대 문구가 비어 확인이 실패한다.
  static func format(_ table: [String: String], _ key: String, _ arguments: any CVarArg...) -> String {
    String(format: table[key] ?? "", arguments: arguments)
  }

  /// 표의 키 값에 인자를 넣은 것과 코드 결과를 비교하는 확인.
  static func check(_ table: [String: String], _ key: String, _ actual: String, _ arguments: any CVarArg...) -> Check {
    Check(key: key, expected: String(format: table[key] ?? "", arguments: arguments), actual: actual)
  }

  /// 여러 줄 문구의 `index` 번째 줄 (없으면 빈 문자열).
  static func line(_ text: String, _ index: Int) -> String {
    let lines = text.components(separatedBy: "\n")
    return index < lines.count ? lines[index] : ""
  }

  static func position(
    app: Int?,
    appID: String? = nil,
    version: Int? = nil,
    versionID: String? = nil
  ) -> BuildCatalogProblem.Position {
    BuildCatalogProblem.Position(appIndex: app, appID: appID, versionIndex: version, versionID: versionID)
  }

  /// 형식 문제 본문의 둘째 줄 (무엇이 어디서 틀렸는지).
  static func detail(_ problem: BuildCatalogProblem) -> String {
    self.line(LauncherText.catalogLoadMessage(for: .catalog(problem), isLocked: false), 1)
  }

  static func load(_ error: DownloadError) -> String {
    LauncherText.catalogLoadMessage(for: .download(error), isLocked: false)
  }

  static func install(_ failure: AppInstallFailure) -> String {
    LauncherText.message(for: failure)
  }
}

// MARK: - 조각

extension CatalogTextCatalog {
  private static func locationChecks(_ table: [String: String]) -> [Check] {
    let app1 = self.format(table, "%lld번째 앱", 1)
    let appA = self.format(table, "%lld번째 앱(id: %@)", 1, "app-a")
    let version3 = self.format(table, "%lld번째 버전", 3)
    let versionV = self.format(table, "%lld번째 버전(id: %@)", 3, "v3")
    return [
      self.check(table, "카탈로그 최상위", LauncherText.catalogLocation(.root)),
      self.check(table, "%lld번째 앱", LauncherText.catalogLocation(self.position(app: 1)), 2),
      self.check(
        table, "%lld번째 앱(id: %@)", LauncherText.catalogLocation(self.position(app: 1, appID: "app-b")), 2, "app-b"
      ),
      Check(
        key: "%lld번째 버전",
        expected: self.format(table, "%@의 %@", app1, version3),
        actual: LauncherText.catalogLocation(self.position(app: 0, version: 2))
      ),
      Check(
        key: "%lld번째 버전(id: %@)",
        expected: self.format(table, "%@의 %@", appA, versionV),
        actual: LauncherText.catalogLocation(self.position(app: 0, appID: "app-a", version: 2, versionID: "v3"))
      ),
      self.check(
        table, "%@의 %@", LauncherText.catalogLocation(self.position(app: 0, appID: "app-a", version: 2)), appA, version3
      ),
    ]
  }

  private static func problemChecks(_ table: [String: String]) -> [Check] {
    let app1 = self.format(table, "%lld번째 앱", 1)
    let appA = self.format(table, "%lld번째 앱(id: %@)", 2, "app-a")
    let item = self.format(table, "%@의 %@", app1, self.format(table, "%lld번째 버전", 2))
    let app = self.position(app: 0)
    let appWithID = self.position(app: 1, appID: "app-a")
    return [
      self.check(
        table, "%@에 필수 필드 %@ 가 없거나 null 입니다.", self.detail(.missingField(.name, position: app)), app1, "name"
      ),
      self.check(table, "%@의 %@ 값의 형식(타입)이 다릅니다.", self.detail(.wrongType(.name, position: app)), app1, "name"),
      self.check(table, "%@의 %@ 가 비어 있습니다.", self.detail(.emptyField(.name, position: app)), app1, "name"),
      self.check(
        table,
        "%@이 객체가 아닙니다 (%@ 배열의 항목은 객체여야 합니다).",
        self.detail(.wrongType(.versions, position: self.position(app: 0, version: 1))),
        item,
        "versions"
      ),
      self.check(
        table,
        "%@의 id 가 형식에 맞지 않습니다 (영문·숫자로 시작하고 영문·숫자·. _ - 만, 128자까지).",
        self.detail(.invalidID(position: app)),
        app1
      ),
      self.check(
        table,
        "%@의 platform 이 ios 나 android 가 아닙니다 (소문자로 씁니다).",
        self.detail(.unsupportedPlatform(position: appWithID)),
        appA
      ),
      self.check(table, "%@의 id 가 앞의 앱과 같습니다 (대소문자 무시).", self.detail(.duplicateAppID(position: appWithID)), appA),
    ]
  }

  /// 버전 문제·규격 문제·끝 줄 조각 (`problemChecks` 다음 순서).
  private static func laterProblemChecks(_ table: [String: String]) -> [Check] {
    let appA = self.format(table, "%lld번째 앱(id: %@)", 2, "app-a")
    let versionV = self.format(table, "%@의 %@", appA, self.format(table, "%lld번째 버전(id: %@)", 2, "v1"))
    let notHTTPS = table["https:// 로 시작하는 주소가 아닙니다"] ?? ""
    let version = self.position(app: 1, appID: "app-a", version: 1, versionID: "v1")
    let invalidID = BuildCatalogProblem.invalidID(position: self.position(app: 0))
    let report = LauncherText.catalogLoadMessage(for: .catalog(invalidID), isLocked: false)
    return [
      self.check(
        table, "%@의 id 가 같은 앱의 앞 버전과 같습니다 (대소문자 무시).", self.detail(.duplicateVersionID(position: version)), versionV
      ),
      self.check(
        table,
        "%@의 createdAt 이 날짜 형식(예: 2026-10-21T04:08:49Z)이 아니거나 없는 날짜·시각입니다.",
        self.detail(.invalidCreatedAt(position: version)),
        versionV
      ),
      self.check(
        table,
        "%@의 buildURL 을 쓸 수 없습니다: %@.",
        self.detail(.invalidBuildURL(.notHTTPS, position: version)),
        versionV,
        notHTTPS
      ),
      self.check(
        table,
        "카탈로그의 schemaVersion %lld 은 없는 규격입니다 (지원: 1~%lld).",
        self.detail(.unsupportedSchemaVersion(0)),
        0,
        BuildCatalog.latestSchemaVersion
      ),
      self.check(table, "카탈로그를 만든 사람에게 알려 주세요.", self.line(report, 2)),
    ]
  }

  private static func reasonChecks(_ table: [String: String]) -> [Check] {
    let reasonKeys = [
      "빈 주소입니다", "주소로 읽을 수 없습니다", "https:// 로 시작하는 주소가 아닙니다", "서버 주소(예: example.com)가 없습니다",
      "사용자 이름이나 비밀번호가 들어 있습니다",
    ]
    var checks: [Check] = zip(reasonKeys, self.urlProblems).map { (key: String, problem: DownloadURLProblem) -> Check in
      self.check(table, key, LauncherText.catalogURLProblemReason(problem))
    }
    checks += [
      self.check(table, "카탈로그를 60초 안에 받지 못해 멈췄습니다. 연결을 확인한 뒤 다시 시도하세요.", self.load(.timedOut)),
      self.check(table, "받는 중 연결이 끊겼습니다. 다시 시도하세요.", self.load(.connectionLost)),
    ]
    return checks
  }
}

// MARK: - 조각이 아닌 새 키

extension CatalogTextCatalog {
  private static func sheetChecks(_ table: [String: String]) -> [Check] {
    let help = [
      "시뮬레이터용 .app 이나 그 .app 을 압축한 zip 을 파일에서 고르거나, https 주소나 등록한 빌드 카탈로그에서 받아 ",
      "이 기기에 설치하고 바로 실행합니다. 이 줄에 .app 이나 zip 을 끌어다 놓아도 됩니다.",
    ].joined()
    return [
      self.check(table, "카탈로그에서…", LauncherText.installFromCatalogMenuItem),
      self.check(table, "앱", LauncherText.catalogAppsHeader),
      self.check(table, "버전", LauncherText.catalogVersionsHeader),
      self.check(table, "카탈로그를 읽는 중…", LauncherText.catalogLoading),
      self.check(table, "이 카탈로그에는 앱이 없습니다.", LauncherText.catalogNoApps),
      self.check(table, "이 카탈로그에는 iOS 앱이 없습니다.", LauncherText.catalogNoIOSApps),
      self.check(table, "이 앱에는 버전이 없습니다.", LauncherText.catalogNoVersions),
      self.check(table, "왼쪽에서 앱을 고르세요.", LauncherText.catalogNoSelection),
      self.check(table, "설정 열기", LauncherText.openSettingsButton),
      self.check(table, "등록된 카탈로그가 없습니다", LauncherText.emptyCatalogTitle),
      self.check(
        table,
        "설정(⌘,)의 “빌드 카탈로그” 에 catalog.json 주소를 등록한 뒤 새로 고침을 누르세요.",
        LauncherText.emptyCatalogMessage(isLocked: false)
      ),
      self.check(
        table,
        "관리자가 정한 카탈로그 목록이 비어 있습니다. Mac 을 관리하는 담당자에게 문의하세요.",
        LauncherText.emptyCatalogMessage(isLocked: true)
      ),
      self.check(table, help, LauncherText.installAppHelp),
    ]
  }

  private static func sheetFormatChecks(_ table: [String: String]) -> [Check] {
    let reason = table["https:// 로 시작하는 주소가 아닙니다"] ?? ""
    let date = Date(timeIntervalSince1970: 1_792_548_529)
    let url = CatalogData.alphaV2URL
    let tagged = BuildCatalog.Version(
      id: .init("t"), name: "t", branch: nil, tag: "v1.1", buildNumber: nil, createdAt: date, buildURL: url
    )
    let branched = BuildCatalog.Version(
      id: .init("b"), name: "b", branch: "main", tag: nil, buildNumber: nil, createdAt: date, buildURL: url
    )
    let built = BuildCatalog.Version(
      id: .init("n"), name: "n", branch: nil, tag: nil, buildNumber: "42", createdAt: date, buildURL: url
    )
    return [
      self.check(
        table, "“%@” (%@) 기기에 카탈로그에서 앱 설치", LauncherText.catalogSheetTitle(for: self.device), "iPhone 17", "iOS 26.0"
      ),
      self.check(
        table,
        "쓸 수 없는 주소라 읽지 않았습니다: %@. 설정(⌘,)에서 지우고 https 주소로 다시 등록하세요.",
        LauncherText.invalidCatalogURL(.notHTTPS, isLocked: false),
        reason
      ),
      self.check(
        table,
        "쓸 수 없는 주소라 읽지 않았습니다: %@. Mac 을 관리하는 담당자에게 알려 주세요.",
        LauncherText.invalidCatalogURL(.notHTTPS, isLocked: true),
        reason
      ),
      self.check(table, "태그 %@", self.firstPart(LauncherText.versionDetail(tagged)), "v1.1"),
      self.check(table, "브랜치 %@", self.firstPart(LauncherText.versionDetail(branched)), "main"),
      self.check(table, "빌드 %@", self.firstPart(LauncherText.versionDetail(built)), "42"),
    ]
  }

  /// 버전 캡션의 첫 조각.
  private static func firstPart(_ caption: String) -> String {
    caption.components(separatedBy: " · ").first ?? ""
  }

  private static func loadChecks(_ table: [String: String]) -> [Check] {
    let notJSON = LauncherText.catalogLoadMessage(for: .catalog(.notJSONObject), isLocked: false)
    let newer = LauncherText.catalogLoadMessage(for: .catalog(.unsupportedSchemaVersion(3)), isLocked: false)
    let tooLarge = [
      "파일이 5 MiB 를 넘어 받지 않았습니다. 설정(⌘,)에서 주소가 catalog.json 파일을 바로 가리키는지 확인하고, ",
      "맞다면 오래된 버전 항목을 지워 달라고 카탈로그를 만든 사람에게 알려 주세요.",
    ].joined()
    return [
      self.check(table, "카탈로그 형식이 맞지 않아 읽지 않았습니다.", self.line(notJSON, 0)),
      self.check(
        table,
        "받은 파일을 카탈로그(JSON 객체)로 읽지 못했습니다. 로그인 페이지 같은 웹 페이지이거나 다른 파일일 수 있습니다.",
        self.line(notJSON, 1)
      ),
      self.check(
        table,
        "설정(⌘,)에서 주소가 catalog.json 파일을 바로 가리키는지 확인하고, 맞다면 카탈로그를 만든 사람에게 알려 주세요.",
        self.line(notJSON, 2)
      ),
      self.check(
        table, "이 카탈로그는 이 앱보다 새 규격(schemaVersion %lld)입니다. SimLauncher 를 업데이트하세요.", self.line(newer, 1), 3
      ),
      self.check(
        table,
        "서버가 https 가 아닌 주소(http 등)로 넘겨 보내 받지 않았습니다. https 로 바로 받을 수 있는지 카탈로그를 만든 사람에게 확인하세요.",
        self.load(.insecureRedirect)
      ),
      self.check(
        table,
        "서버 주소를 찾지 못했습니다. 회사 안의 주소라면 사내망(VPN 등)에 연결되어 있는지 확인하고, 아니면 설정(⌘,)에서 주소의 철자를 확인하세요.",
        self.load(.hostNotFound)
      ),
      self.check(
        table,
        "서버에 연결하지 못했습니다. 회사 안의 주소라면 사내망(VPN 등) 연결과 프록시 설정을 확인하고, 아니면 설정(⌘,)에서 주소를 확인하세요.",
        self.load(.cannotConnect)
      ),
      self.check(
        table,
        "서버와 보안 연결(TLS)을 맺지 못했습니다(인증서 문제 등). 설정(⌘,)에서 주소가 맞는지 확인하고, 계속되면 서버 관리자에게 알려 주세요.",
        self.load(.secureConnectionFailed)
      ),
      self.check(table, tooLarge, self.load(.tooLarge)),
      self.check(table, "카탈로그를 받지 못했습니다. 다시 시도하고, 계속되면 설정(⌘,)에서 주소를 확인하세요.", self.load(.failed)),
    ]
  }

  private static func loadStatusChecks(_ table: [String: String]) -> [Check] {
    let denied = [
      "서버가 접근을 거부해 받지 못했습니다 (HTTP %lld). 설정(⌘,)에서 주소가 맞는지 확인하고, ",
      "맞다면 로그인 없이 받을 수 있는 주소인지 카탈로그를 만든 사람에게 확인하세요.",
    ].joined()
    return [
      self.check(table, denied, self.load(.httpStatus(401)), 401),
      self.check(
        table,
        "서버에 카탈로그 파일이 없습니다 (HTTP %lld). 설정(⌘,)에서 주소가 맞는지 확인하고, 맞다면 카탈로그를 만든 사람에게 알려 주세요.",
        self.load(.httpStatus(404)),
        404
      ),
      self.check(
        table,
        "서버가 카탈로그를 주지 않았습니다 (HTTP %lld). 설정(⌘,)에서 주소를 확인한 뒤 다시 시도하세요.",
        self.load(.httpStatus(400)),
        400
      ),
    ]
  }

  private static func installChecks(_ table: [String: String]) -> [Check] {
    let insecure = [
      "서버가 https 가 아닌 주소(http 등)로 넘겨 보내 빌드를 받지 않았습니다. ",
      "이 버전의 빌드를 https 로 바로 받을 수 있게 해 달라고 카탈로그를 만든 사람에게 알려 주세요.",
    ].joined()
    let webPage = [
      "zip 파일 대신 웹 페이지를 받았습니다. 이 버전의 빌드 주소가 로그인이 필요한 주소이거나 내려받기 페이지일 수 있습니다. ",
      "카탈로그를 만든 사람에게 알려 주세요.",
    ].joined()
    let withoutApp = [
      "받은 zip 맨 위에 .app 이 없습니다. .ipa 이거나 .app 이 폴더 안에 있을 수 있습니다. ",
      "시뮬레이터용 .app 을 바로 압축한 zip 을 올려 달라고 카탈로그를 만든 사람에게 알려 주세요.",
    ].joined()
    return [
      self.check(table, insecure, self.install(.catalogDownload(.insecureRedirect))),
      self.check(
        table,
        "빌드 서버 주소를 찾지 못했습니다. 회사 안의 주소라면 사내망(VPN 등)에 연결되어 있는지 확인하고, 계속되면 카탈로그를 만든 사람에게 알려 주세요.",
        self.install(.catalogDownload(.hostNotFound))
      ),
      self.check(
        table,
        "빌드 서버에 연결하지 못했습니다. 회사 안의 주소라면 사내망(VPN 등) 연결과 프록시 설정을 확인하고, 계속되면 카탈로그를 만든 사람에게 알려 주세요.",
        self.install(.catalogDownload(.cannotConnect))
      ),
      self.check(
        table,
        "빌드 서버와 보안 연결(TLS)을 맺지 못했습니다(인증서 문제 등). 계속되면 서버 관리자나 카탈로그를 만든 사람에게 알려 주세요.",
        self.install(.catalogDownload(.secureConnectionFailed))
      ),
      self.check(
        table,
        "빌드 파일을 받지 못했습니다. 다시 시도하고, 계속되면 카탈로그를 만든 사람에게 알려 주세요.",
        self.install(.catalogDownload(.failed))
      ),
      self.check(table, webPage, self.install(.catalogDownloadedNotZip(isWebPage: true))),
      self.check(
        table,
        "받은 파일이 zip 이 아니거나 손상되었습니다. 다시 시도하고, 계속되면 카탈로그를 만든 사람에게 알려 주세요.",
        self.install(.catalogDownloadedNotZip(isWebPage: false))
      ),
      self.check(table, withoutApp, self.install(.catalogDownloadedZip(.zipWithoutApp))),
      self.check(
        table,
        "받은 zip 맨 위에 .app 이 여러 개 있습니다. .app 하나만 압축한 zip 을 올려 달라고 카탈로그를 만든 사람에게 알려 주세요.",
        self.install(.catalogDownloadedZip(.zipWithMultipleApps))
      ),
    ]
  }

  private static func installStatusChecks(_ table: [String: String]) -> [Check] {
    let denied = [
      "서버가 접근을 거부해 빌드를 받지 못했습니다 (HTTP %lld). 지워졌거나 로그인이 필요한 빌드일 수 있습니다. ",
      "다른 버전을 고르거나 카탈로그를 만든 사람에게 알려 주세요.",
    ].joined()
    return [
      self.check(table, denied, self.install(.catalogDownload(.httpStatus(403))), 403),
      self.check(
        table,
        "서버에 이 버전의 빌드 파일이 없습니다 (HTTP %lld). 지워진 빌드일 수 있습니다. 다른 버전을 고르거나 카탈로그를 만든 사람에게 알려 주세요.",
        self.install(.catalogDownload(.httpStatus(410))),
        410
      ),
      self.check(
        table,
        "서버가 빌드 파일을 주지 않았습니다 (HTTP %lld). 다시 시도하고, 계속되면 카탈로그를 만든 사람에게 알려 주세요.",
        self.install(.catalogDownload(.httpStatus(418))),
        418
      ),
    ]
  }
}

// MARK: - 잠긴 목록의 카탈로그 읽기 실패

extension CatalogTextCatalog {
  static func lockedLoad(_ error: DownloadError) -> String {
    LauncherText.catalogLoadMessage(for: .download(error), isLocked: true)
  }

  private static func lockedLoadChecks(_ table: [String: String]) -> [Check] {
    let notJSON = LauncherText.catalogLoadMessage(for: .catalog(.notJSONObject), isLocked: true)
    let denied = [
      "서버가 접근을 거부해 받지 못했습니다 (HTTP %lld). Mac 을 관리하는 담당자에게 주소가 맞는지 확인해 달라고 하고, ",
      "맞다면 로그인 없이 받을 수 있는 주소인지 카탈로그를 만든 사람에게 확인하세요.",
    ].joined()
    let missing = [
      "서버에 카탈로그 파일이 없습니다 (HTTP %lld). Mac 을 관리하는 담당자에게 주소가 맞는지 확인해 달라고 하고, ",
      "맞다면 카탈로그를 만든 사람에게 알려 주세요.",
    ].joined()
    let tooLarge = [
      "파일이 5 MiB 를 넘어 받지 않았습니다. Mac 을 관리하는 담당자에게 주소가 catalog.json 파일을 바로 가리키는지 ",
      "확인해 달라고 하고, 맞다면 오래된 버전 항목을 지워 달라고 카탈로그를 만든 사람에게 알려 주세요.",
    ].joined()
    return [
      self.check(table, denied, self.lockedLoad(.httpStatus(401)), 401),
      self.check(table, missing, self.lockedLoad(.httpStatus(404)), 404),
      self.check(
        table,
        "서버가 카탈로그를 주지 않았습니다 (HTTP %lld). 다시 시도하고, 계속되면 Mac 을 관리하는 담당자에게 주소를 확인해 달라고 하세요.",
        self.lockedLoad(.httpStatus(400)),
        400
      ),
      self.check(
        table,
        "서버 주소를 찾지 못했습니다. 회사 안의 주소라면 사내망(VPN 등)에 연결되어 있는지 확인하고, 아니면 Mac 을 관리하는 담당자에게 주소의 철자를 확인해 달라고 하세요.",
        self.lockedLoad(.hostNotFound)
      ),
      self.check(
        table,
        "서버에 연결하지 못했습니다. 회사 안의 주소라면 사내망(VPN 등) 연결과 프록시 설정을 확인하고, 아니면 Mac 을 관리하는 담당자에게 주소를 확인해 달라고 하세요.",
        self.lockedLoad(.cannotConnect)
      ),
      self.check(
        table,
        "서버와 보안 연결(TLS)을 맺지 못했습니다(인증서 문제 등). Mac 을 관리하는 담당자에게 주소가 맞는지 확인해 달라고 하고, 계속되면 서버 관리자에게 알려 주세요.",
        self.lockedLoad(.secureConnectionFailed)
      ),
      self.check(table, tooLarge, self.lockedLoad(.tooLarge)),
      self.check(
        table,
        "카탈로그를 받지 못했습니다. 다시 시도하고, 계속되면 Mac 을 관리하는 담당자에게 주소를 확인해 달라고 하세요.",
        self.lockedLoad(.failed)
      ),
      self.check(
        table,
        "Mac 을 관리하는 담당자에게 주소가 catalog.json 파일을 바로 가리키는지 확인해 달라고 하고, 맞다면 카탈로그를 만든 사람에게 알려 주세요.",
        self.line(notJSON, 2)
      ),
    ]
  }
}
