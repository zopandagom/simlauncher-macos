import Core
import DownloadInterface
import Foundation
@testable import AndroidDevicesFeature

/// 카탈로그 읽기 실패 문구의 확인 (`DownloadTextCatalog.sharedChecks` 가 모은다). Launcher `CatalogTextCatalog` 의 같은 확인을
/// 이 모듈 문구 함수로 옮긴 것이다.
extension DownloadTextCatalog {
  static func locationChecks(_ table: [String: String]) -> [Check] {
    let app1 = self.format(table, "%lld번째 앱", 1)
    let appA = self.format(table, "%lld번째 앱(id: %@)", 1, "app-a")
    let version3 = self.format(table, "%lld번째 버전", 3)
    let versionV = self.format(table, "%lld번째 버전(id: %@)", 3, "v3")
    return [
      self.check(table, "카탈로그 최상위", AndroidDevicesText.catalogLocation(.root)),
      self.check(table, "%lld번째 앱", AndroidDevicesText.catalogLocation(self.position(app: 1)), 2),
      self.check(
        table,
        "%lld번째 앱(id: %@)",
        AndroidDevicesText.catalogLocation(self.position(app: 1, appID: "app-b")),
        2,
        "app-b"
      ),
      Check(
        key: "%lld번째 버전",
        expected: self.format(table, "%@의 %@", app1, version3),
        actual: AndroidDevicesText.catalogLocation(self.position(app: 0, version: 2))
      ),
      Check(
        key: "%lld번째 버전(id: %@)",
        expected: self.format(table, "%@의 %@", appA, versionV),
        actual: AndroidDevicesText.catalogLocation(self.position(app: 0, appID: "app-a", version: 2, versionID: "v3"))
      ),
      self.check(
        table,
        "%@의 %@",
        AndroidDevicesText.catalogLocation(self.position(app: 0, appID: "app-a", version: 2)),
        appA,
        version3
      ),
    ]
  }

  static func problemChecks(_ table: [String: String]) -> [Check] {
    let app1 = self.format(table, "%lld번째 앱", 1)
    let appA = self.format(table, "%lld번째 앱(id: %@)", 2, "app-a")
    let item = self.format(table, "%@의 %@", app1, self.format(table, "%lld번째 버전", 2))
    let app = self.position(app: 0)
    let appWithID = self.position(app: 1, appID: "app-a")
    return [
      self.check(
        table, "%@에 필수 필드 %@ 가 없거나 null 입니다.", self.detail(.missingField(.platform, position: appWithID)), appA,
        "platform"
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
    ]
  }

  /// 형식 문제 중 중복·날짜·주소·규격과 다음 할 일 줄 (`problemChecks` 를 나눈 뒤쪽).
  static func laterProblemChecks(_ table: [String: String]) -> [Check] {
    let appA = self.format(table, "%lld번째 앱(id: %@)", 2, "app-a")
    let versionV = self.format(table, "%@의 %@", appA, self.format(table, "%lld번째 버전(id: %@)", 2, "v1"))
    let notHTTPS = table["https:// 로 시작하는 주소가 아닙니다"] ?? ""
    let appWithID = self.position(app: 1, appID: "app-a")
    let version = self.position(app: 1, appID: "app-a", version: 1, versionID: "v1")
    let report = AndroidDevicesText.catalogLoadMessage(
      for: .catalog(.invalidID(position: self.position(app: 0))),
      isLocked: false
    )
    return [
      self.check(table, "%@의 id 가 앞의 앱과 같습니다 (대소문자 무시).", self.detail(.duplicateAppID(position: appWithID)), appA),
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
        table, "카탈로그의 schemaVersion %lld 은 없는 규격입니다 (지원: 1~%lld).", self.detail(.unsupportedSchemaVersion(0)), 0, 2
      ),
      self.check(table, "카탈로그를 만든 사람에게 알려 주세요.", self.line(report, 2)),
    ]
  }

  static func reasonChecks(_ table: [String: String]) -> [Check] {
    let reasons: [(String, DownloadURLProblem)] = [
      ("빈 주소입니다", .empty), ("주소로 읽을 수 없습니다", .malformed), ("https:// 로 시작하는 주소가 아닙니다", .notHTTPS),
      ("서버 주소(예: example.com)가 없습니다", .missingHost), ("사용자 이름이나 비밀번호가 들어 있습니다", .hasCredentials),
    ]
    return reasons.map { key, problem in
      self.check(table, key, AndroidDevicesText.catalogURLProblemReason(problem))
    } + [
      self.check(table, "카탈로그를 60초 안에 받지 못해 멈췄습니다. 연결을 확인한 뒤 다시 시도하세요.", self.load(.timedOut)),
      self.check(table, "받는 중 연결이 끊겼습니다. 다시 시도하세요.", self.load(.connectionLost)),
    ]
  }

  static func loadChecks(_ table: [String: String]) -> [Check] {
    let notJSON = AndroidDevicesText.catalogLoadMessage(for: .catalog(.notJSONObject), isLocked: false)
    let newer = AndroidDevicesText.catalogLoadMessage(for: .catalog(.unsupportedSchemaVersion(3)), isLocked: false)
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

  static func loadStatusChecks(_ table: [String: String]) -> [Check] {
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

  static func lockedLoadChecks(_ table: [String: String]) -> [Check] {
    let notJSON = AndroidDevicesText.catalogLoadMessage(for: .catalog(.notJSONObject), isLocked: true)
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
