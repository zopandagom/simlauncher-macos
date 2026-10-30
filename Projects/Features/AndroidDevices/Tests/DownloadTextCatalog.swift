import AndroidEmulatorInterface
import AndroidEmulatorTesting
import AndroidPackageInterface
import Core
import DownloadInterface
import Foundation
@testable import AndroidDevicesFeature

/// URL·카탈로그에서 설치 문구(`AndroidDevicesText+Download.swift`·`+Catalog.swift`·`+CatalogLoad.swift`)의 String Catalog 키.
/// 확인 한 줄마다 키, 표의 값으로 만든 기대 문구(보간 키는 인자를 넣은 값), 같은 인자로 부른 문구 함수의 결과를 담는다.
/// 표를 인자로 받아, `AndroidDevicesResourcesTests` 는 이 모듈의 컴파일된 표로 모든 키를, `LauncherTextSyncTests` 는 Launcher
/// 원본 표로 공유 키(`sharedChecks`)를 본다.
enum DownloadTextCatalog {
  struct Check {
    let key: String
    let expected: String
    let actual: String
  }

  static let device = AndroidDeviceLabel(.phoneSample)

  /// iOS 기기 목록(Launcher)과 같은 키·값으로 둔 문구.
  static func sharedChecks(_ table: [String: String]) -> [Check] {
    var checks = self.rowChecks(table)
    checks += self.sheetChecks(table)
    checks += self.urlDownloadChecks(table)
    checks += self.urlStatusChecks(table)
    checks += self.catalogInstallChecks(table)
    checks += self.locationChecks(table)
    checks += self.problemChecks(table)
    checks += self.laterProblemChecks(table)
    checks += self.reasonChecks(table)
    checks += self.loadChecks(table)
    checks += self.loadStatusChecks(table)
    checks += self.lockedLoadChecks(table)
    return checks
  }

  /// Android 문장 (시트 제목·예시·안내, Android 앱이 없는 구역, 받은 apk 실패).
  static func androidChecks(_ table: [String: String]) -> [Check] {
    let label = AndroidDevicesText.label(self.device)
    let help = [
      ".apk 파일을 고르거나, https 주소나 등록한 빌드 카탈로그에서 받아 이 기기에 설치하고 바로 실행합니다. ",
      "이 줄에 .apk 를 끌어다 놓아도 됩니다.",
    ].joined()
    let schemaVersion1 = [
      "이 카탈로그는 schemaVersion 1 이라 iOS 앱만 담습니다. ",
      "Android 앱을 받으려면 카탈로그를 만든 사람에게 schemaVersion 2 로 바꿔 달라고 알려 주세요.",
    ].joined()
    return [
      self.check(table, "%@ 기기에 URL 에서 앱 설치", AndroidDevicesText.installURLSheetTitle(for: self.device), label),
      self.check(table, "%@ 기기에 카탈로그에서 앱 설치", AndroidDevicesText.catalogSheetTitle(for: self.device), label),
      self.check(table, "예: https://example.com/MyApp.apk", AndroidDevicesText.downloadURLPrompt),
      self.check(
        table,
        "기기에 설치할 .apk 파일의 https 주소를 입력하세요. 로그인이 필요한 주소에서는 받을 수 없습니다.",
        AndroidDevicesText.downloadURLGuide
      ),
      self.check(table, help, AndroidDevicesText.installAppHelp),
      self.check(table, "이 카탈로그에는 Android 앱이 없습니다.", AndroidDevicesText.catalogEmptyReason(.noAndroidApps)),
      self.check(table, schemaVersion1, AndroidDevicesText.catalogEmptyReason(.schemaVersion1)),
    ] + self.downloadedPackageChecks(table)
  }
}

// MARK: - 도움 함수

extension DownloadTextCatalog {
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
    self.line(AndroidDevicesText.catalogLoadMessage(for: .catalog(problem), isLocked: false), 1)
  }

  static func load(_ error: DownloadError) -> String {
    AndroidDevicesText.catalogLoadMessage(for: .download(error), isLocked: false)
  }

  static func lockedLoad(_ error: DownloadError) -> String {
    AndroidDevicesText.catalogLoadMessage(for: .download(error), isLocked: true)
  }

  /// 알림 본문을 거친 받기 실패 (출처가 문구를 고른다).
  static func download(_ error: DownloadError, _ origin: AndroidDownloadOrigin) -> String {
    AndroidDevicesText.message(for: AndroidAppInstallFailure.download(error, origin: origin))
  }

  /// 알림 본문을 거친 받은 파일의 apk 검사 실패.
  static func package(
    _ error: AndroidPackageError,
    isWebPage: Bool = false,
    _ origin: AndroidDownloadOrigin
  ) -> String {
    AndroidDevicesText.message(for: AndroidAppInstallFailure.downloadedPackage(
      error,
      isWebPage: isWebPage,
      origin: origin
    ))
  }
}

// MARK: - 행·시트 (공유)

extension DownloadTextCatalog {
  private static func rowChecks(_ table: [String: String]) -> [Check] {
    let received = Int64(1_500_000).formatted(.byteCount(style: .file))
    let total = Int64(12_000_000).formatted(.byteCount(style: .file))
    let partial = DownloadProgress(receivedBytes: 1_500_000, expectedBytes: nil)
    let full = DownloadProgress(receivedBytes: 1_500_000, expectedBytes: 12_000_000)
    return [
      self.check(table, "URL 에서…", AndroidDevicesText.installFromURLMenuItem),
      self.check(table, "카탈로그에서…", AndroidDevicesText.installFromCatalogMenuItem),
      self.check(table, "받는 중…", AndroidDevicesText.downloadingLabel(nil)),
      self.check(table, "받는 중… %@", AndroidDevicesText.downloadingLabel(partial), received),
      self.check(table, "받는 중… %@ / %@", AndroidDevicesText.downloadingLabel(full), received, total),
      self.check(table, "취소하는 중…", AndroidDevicesText.cancellingDownloadLabel),
      self.check(table, "받기 취소", AndroidDevicesText.cancelDownloadAccessibilityLabel),
      self.check(table, "받기를 멈추고 받은 부분을 지웁니다", AndroidDevicesText.cancelDownloadHelp),
      self.check(table, "주소", AndroidDevicesText.downloadURLField),
      self.check(table, "받아서 설치", AndroidDevicesText.installURLConfirmButton),
      self.check(table, "취소", AndroidDevicesText.cancelButton),
      self.check(table, "새로 고침", AndroidDevicesText.refreshButton),
      self.check(
        table,
        "주소로 읽을 수 없습니다. 공백이나 쓸 수 없는 문자가 섞이지 않았는지 확인하세요.",
        AndroidDevicesText.downloadURLProblem(.malformed) ?? ""
      ),
      self.check(
        table, "https:// 로 시작하는 주소만 받을 수 있습니다.", AndroidDevicesText.downloadURLProblem(.notHTTPS) ?? ""
      ),
      self.check(
        table,
        "https:// 뒤에 서버 주소(예: example.com)를 입력하세요.",
        AndroidDevicesText.downloadURLProblem(.missingHost) ?? ""
      ),
      self.check(
        table,
        "사용자 이름이나 비밀번호가 든 주소는 쓸 수 없습니다. 로그인 없이 받을 수 있는 주소를 입력하세요.",
        AndroidDevicesText.downloadURLProblem(.hasCredentials) ?? ""
      ),
    ]
  }

  private static func sheetChecks(_ table: [String: String]) -> [Check] {
    let reason = table["https:// 로 시작하는 주소가 아닙니다"] ?? ""
    let date = Date(timeIntervalSince1970: 1_792_548_529)
    let url = DownloadURL("https://builds.example.com/a.apk")!
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
      self.check(table, "앱", AndroidDevicesText.catalogAppsHeader),
      self.check(table, "버전", AndroidDevicesText.catalogVersionsHeader),
      self.check(table, "카탈로그를 읽는 중…", AndroidDevicesText.catalogLoading),
      self.check(table, "이 카탈로그에는 앱이 없습니다.", AndroidDevicesText.catalogEmptyReason(.noApps)),
      self.check(table, "이 앱에는 버전이 없습니다.", AndroidDevicesText.catalogNoVersions),
      self.check(table, "왼쪽에서 앱을 고르세요.", AndroidDevicesText.catalogNoSelection),
      self.check(table, "설정 열기", AndroidDevicesText.openSettingsButton),
      self.check(table, "등록된 카탈로그가 없습니다", AndroidDevicesText.emptyCatalogTitle),
      self.check(
        table,
        "설정(⌘,)의 “빌드 카탈로그” 에 catalog.json 주소를 등록한 뒤 새로 고침을 누르세요.",
        AndroidDevicesText.emptyCatalogMessage(isLocked: false)
      ),
      self.check(
        table,
        "관리자가 정한 카탈로그 목록이 비어 있습니다. Mac 을 관리하는 담당자에게 문의하세요.",
        AndroidDevicesText.emptyCatalogMessage(isLocked: true)
      ),
      self.check(
        table,
        "쓸 수 없는 주소라 읽지 않았습니다: %@. 설정(⌘,)에서 지우고 https 주소로 다시 등록하세요.",
        AndroidDevicesText.catalogSourceNote(.invalid(.notHTTPS, isLocked: false)),
        reason
      ),
      self.check(
        table,
        "쓸 수 없는 주소라 읽지 않았습니다: %@. Mac 을 관리하는 담당자에게 알려 주세요.",
        AndroidDevicesText.catalogSourceNote(.invalid(.notHTTPS, isLocked: true)),
        reason
      ),
      self.check(table, "태그 %@", self.firstPart(AndroidDevicesText.versionDetail(tagged)), "v1.1"),
      self.check(table, "브랜치 %@", self.firstPart(AndroidDevicesText.versionDetail(branched)), "main"),
      self.check(table, "빌드 %@", self.firstPart(AndroidDevicesText.versionDetail(built)), "42"),
    ]
  }

  /// 버전 캡션의 첫 조각.
  private static func firstPart(_ caption: String) -> String {
    caption.components(separatedBy: " · ").first ?? ""
  }
}

// MARK: - 받기 실패 (공유)

extension DownloadTextCatalog {
  private static func urlDownloadChecks(_ table: [String: String]) -> [Check] {
    let insecure = [
      "서버가 안전하지 않은 주소(http)로 넘겨 보내 받지 않았습니다. ",
      "https 로 바로 받을 수 있는 주소인지 빌드를 올린 사람에게 확인하세요.",
    ].joined()
    return [
      self.check(table, insecure, self.download(.insecureRedirect, .enteredURL)),
      self.check(table, "인터넷에 연결되어 있지 않습니다. 연결을 확인한 뒤 다시 시도하세요.", self.download(.offline, .enteredURL)),
      self.check(
        table,
        "서버 주소를 찾지 못했습니다. 주소의 철자를 확인하고, 회사 안의 주소라면 사내망(VPN 등)에 연결되어 있는지 확인하세요.",
        self.download(.hostNotFound, .enteredURL)
      ),
      self.check(
        table,
        "서버에 연결하지 못했습니다. 주소를 확인하고, 회사 안의 주소라면 사내망(VPN 등) 연결과 프록시 설정을 확인하세요.",
        self.download(.cannotConnect, .enteredURL)
      ),
      self.check(table, "서버가 오래 응답하지 않아 멈췄습니다. 연결을 확인한 뒤 다시 시도하세요.", self.download(.timedOut, .enteredURL)),
      self.check(table, "받는 중 연결이 끊겨 받은 부분을 지웠습니다. 다시 시도하세요.", self.download(.connectionLost, .enteredURL)),
      self.check(
        table,
        "서버의 보안 인증서를 확인하지 못해 받지 않았습니다. 주소가 맞는지 확인하고, 계속되면 서버 관리자에게 알려 주세요.",
        self.download(.secureConnectionFailed, .enteredURL)
      ),
      self.check(
        table,
        "Mac 의 저장 공간이 부족해 받지 못했습니다. 공간을 확보한 뒤 다시 시도하세요.",
        self.download(.insufficientDiskSpace, .enteredURL)
      ),
      self.check(
        table,
        "받은 파일을 둘 임시 폴더를 준비하지 못했습니다. 잠시 뒤 다시 시도하고, 계속되면 Mac 을 다시 시작해 보세요.",
        self.download(.storageUnavailable, .enteredURL)
      ),
      self.check(table, "파일을 받지 못했습니다. 주소를 확인한 뒤 다시 시도하세요.", self.download(.failed, .enteredURL)),
    ]
  }

  private static func urlStatusChecks(_ table: [String: String]) -> [Check] {
    let proxy = "이 Mac 이 쓰는 프록시가 인증을 요구해 받지 못했습니다 (HTTP 407). 회사 네트워크라면 관리자에게 프록시 설정을 문의하세요."
    return [
      self.check(
        table,
        "서버가 로그인이나 접근 권한을 요구해 받지 못했습니다 (HTTP %lld). 로그인 없이 받을 수 있는 주소인지 확인하세요.",
        self.download(.httpStatus(401), .enteredURL),
        401
      ),
      self.check(table, proxy, self.download(.httpStatus(407), .enteredURL)),
      self.check(
        table,
        "서버에 파일이 없습니다 (HTTP %lld). 주소가 맞는지, 파일이 지워지지 않았는지 확인하세요.",
        self.download(.httpStatus(404), .enteredURL),
        404
      ),
      self.check(
        table, "서버 오류로 받지 못했습니다 (HTTP %lld). 잠시 뒤 다시 시도하세요.", self.download(.httpStatus(503), .enteredURL), 503
      ),
      self.check(
        table,
        "서버가 파일을 주지 않았습니다 (HTTP %lld). 주소를 확인한 뒤 다시 시도하세요.",
        self.download(.httpStatus(418), .enteredURL),
        418
      ),
    ]
  }

  private static func catalogInstallChecks(_ table: [String: String]) -> [Check] {
    let insecure = [
      "서버가 https 가 아닌 주소(http 등)로 넘겨 보내 빌드를 받지 않았습니다. ",
      "이 버전의 빌드를 https 로 바로 받을 수 있게 해 달라고 카탈로그를 만든 사람에게 알려 주세요.",
    ].joined()
    let denied = [
      "서버가 접근을 거부해 빌드를 받지 못했습니다 (HTTP %lld). 지워졌거나 로그인이 필요한 빌드일 수 있습니다. ",
      "다른 버전을 고르거나 카탈로그를 만든 사람에게 알려 주세요.",
    ].joined()
    return [
      self.check(table, insecure, self.download(.insecureRedirect, .catalog)),
      self.check(
        table,
        "빌드 서버 주소를 찾지 못했습니다. 회사 안의 주소라면 사내망(VPN 등)에 연결되어 있는지 확인하고, 계속되면 카탈로그를 만든 사람에게 알려 주세요.",
        self.download(.hostNotFound, .catalog)
      ),
      self.check(
        table,
        "빌드 서버에 연결하지 못했습니다. 회사 안의 주소라면 사내망(VPN 등) 연결과 프록시 설정을 확인하고, 계속되면 카탈로그를 만든 사람에게 알려 주세요.",
        self.download(.cannotConnect, .catalog)
      ),
      self.check(
        table,
        "빌드 서버와 보안 연결(TLS)을 맺지 못했습니다(인증서 문제 등). 계속되면 서버 관리자나 카탈로그를 만든 사람에게 알려 주세요.",
        self.download(.secureConnectionFailed, .catalog)
      ),
      self.check(
        table,
        "빌드 파일을 받지 못했습니다. 다시 시도하고, 계속되면 카탈로그를 만든 사람에게 알려 주세요.",
        self.download(.failed, .catalog)
      ),
      self.check(table, denied, self.download(.httpStatus(403), .catalog), 403),
      self.check(
        table,
        "서버에 이 버전의 빌드 파일이 없습니다 (HTTP %lld). 지워진 빌드일 수 있습니다. 다른 버전을 고르거나 카탈로그를 만든 사람에게 알려 주세요.",
        self.download(.httpStatus(410), .catalog),
        410
      ),
      self.check(
        table,
        "서버가 빌드 파일을 주지 않았습니다 (HTTP %lld). 다시 시도하고, 계속되면 카탈로그를 만든 사람에게 알려 주세요.",
        self.download(.httpStatus(418), .catalog),
        418
      ),
      self.check(table, "받은 파일을 읽지 못했습니다. 다시 시도하세요.", self.package(.notAPK, .enteredURL)),
    ]
  }
}

// MARK: - 받은 apk 실패 (Android)

extension DownloadTextCatalog {
  private static func downloadedPackageChecks(_ table: [String: String]) -> [Check] {
    let webPage = [
      "apk 파일 대신 웹 페이지를 받았습니다. 로그인이 필요한 주소이거나 내려받기 페이지의 주소일 수 있습니다. ",
      "로그인 없이 apk 파일을 바로 받을 수 있는 주소를 입력하세요.",
    ].joined()
    let unreadable = [
      "받은 파일이 apk 가 아니거나 손상되었습니다. 주소가 .apk 파일을 바로 가리키는지 확인하세요 ",
      "(zip 으로 감싸거나 .apks 묶음이면 설치할 수 없습니다).",
    ].joined()
    let catalogWebPage = [
      "apk 파일 대신 웹 페이지를 받았습니다. 이 버전의 빌드 주소가 로그인이 필요한 주소이거나 내려받기 페이지일 수 있습니다. ",
      "카탈로그를 만든 사람에게 알려 주세요.",
    ].joined()
    let catalogBundle = [
      "이 버전의 빌드는 App Bundle(.aab)이라 기기에 바로 설치할 수 없습니다. ",
      ".apk 를 올려 달라고 카탈로그를 만든 사람에게 알려 주세요.",
    ].joined()
    return [
      self.check(table, webPage, self.package(.unreadable, isWebPage: true, .enteredURL)),
      self.check(table, unreadable, self.package(.unreadable, .enteredURL)),
      self.check(
        table,
        "받은 파일은 App Bundle(.aab)이라 기기에 바로 설치할 수 없습니다. .apk 파일의 주소를 입력하세요.",
        self.package(.appBundle, .enteredURL)
      ),
      self.check(table, catalogWebPage, self.package(.unreadable, isWebPage: true, .catalog)),
      self.check(
        table,
        "받은 파일이 apk 가 아니거나 손상되었습니다. 다시 시도하고, 계속되면 카탈로그를 만든 사람에게 알려 주세요.",
        self.package(.unreadable, .catalog)
      ),
      self.check(table, catalogBundle, self.package(.appBundle, .catalog)),
      self.check(
        table,
        "이 버전의 apk 는 서명되지 않아 설치할 수 없습니다. 카탈로그를 만든 사람에게 알려 주세요.",
        self.package(.unsigned, .catalog)
      ),
    ]
  }
}
