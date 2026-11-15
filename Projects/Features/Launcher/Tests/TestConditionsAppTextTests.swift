import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

/// 테스트 조건 앱 단위 구역 문구(`LauncherText+AppConditions.swift`)의 String Catalog 키. `LauncherResourcesTests` 가 컴파일된 표로
/// 모든 키를 본다. "(공통)" 키는 Android 기기 목록의 `LauncherTextSyncTests` 가 Launcher 원본 카탈로그로 다시 본다.
enum AppConditionsTextCatalog {
  typealias Check = CatalogTextCatalog.Check

  static let app = InstalledApp(
    bundleID: AppBundleID("com.example.sample")!,
    displayName: "Sample",
    version: nil,
    build: nil
  )

  static func checks(_ table: [String: String]) -> [Check] {
    self.appChecks(table) + self.privacyChecks(table) + self.pushChecks(table) + self.problemChecks(table)
      + self.formatChecks(table)
  }

  private static func pairs(_ table: [String: String], _ pairs: [(String, String)]) -> [Check] {
    pairs.map { CatalogTextCatalog.check(table, $0.0, $0.1) }
  }

  private static func appChecks(_ table: [String: String]) -> [Check] {
    self.pairs(table, [
      ("앱", LauncherText.appSection),
      ("앱을 고르세요", LauncherText.noAppSelected),
      ("앱 목록을 읽는 중…", LauncherText.readingApps),
      ("앱 목록을 읽지 못했습니다.", LauncherText.appsReadFailed),
      ("이 기기에 설치한 앱이 없습니다. 앱을 설치한 뒤 앱 목록 다시 읽기를 누르세요.", LauncherText.noInstalledAppsForConditions),
      ("앱 목록 다시 읽기", LauncherText.refreshAppsButton),
      ("시트를 연 뒤 설치한 앱은 앱 목록 다시 읽기로 보입니다.", LauncherText.appsRefreshNote),
      ("위에서 앱을 고르세요.", LauncherText.selectAppFirst),
    ])
  }

  private static func privacyChecks(_ table: [String: String]) -> [Check] {
    var pairs: [(String, String)] = [
      ("권한", LauncherText.privacySection),
      ("바꾸기", LauncherText.privacyChangeMenu),
      (
        "iOS 는 권한의 지금 상태를 알려 주지 않아, SimLauncher 가 켜져 있는 동안 바꾼 값만 보입니다.",
        LauncherText.privacyStateNote
      ),
      (
        "위치 밖의 권한을 바꾸면 실행 중인 앱이 종료됩니다(값이 같아도). SimLauncher 로 실행해 로그를 받던 앱이면 로그도 끝납니다.",
        LauncherText.privacyTerminationNote
      ),
      ("알림 권한은 바꿀 수 없습니다. 앱에서 알림을 허용하세요.", LauncherText.notificationPermissionNote),
    ]
    let services = [
      "위치 (사용하는 동안)", "위치 (항상)", "카메라", "마이크", "사진", "사진 추가", "연락처", "캘린더", "미리 알림",
      "동작 및 피트니스", "미디어 및 Apple Music",
    ]
    pairs += zip(services, IOSPrivacyService.allCases.map(LauncherText.privacyServiceName)).map { ($0, $1) }
    let actions = ["허용", "거부", "다시 묻기 (초기화)"]
    pairs += zip(actions, IOSPrivacyAction.allCases.map(LauncherText.privacyActionName)).map { ($0, $1) }
    return self.pairs(table, pairs)
  }

  private static func pushChecks(_ table: [String: String]) -> [Check] {
    self.pairs(table, [
      ("푸시 알림", LauncherText.pushSection),
      ("입력 방식", LauncherText.pushInputLabel),
      ("제목·본문", LauncherText.pushInputName(.form)),
      ("JSON", LauncherText.pushInputName(.json)),
      ("제목 (선택)", LauncherText.pushTitleField),
      ("본문", LauncherText.pushBodyField),
      ("보내기", LauncherText.sendPushButton),
      (
        "앱이 알림 권한을 받아야 알림이 보입니다. 권한이 없으면 iOS 버전에 따라 '보냈습니다' 로 나와도 화면에 보이지 않을 수 있습니다.",
        LauncherText.pushAuthorizationNote
      ),
      ("테스트 알림", LauncherText.pushExampleTitle),
      ("SimLauncher 가 보낸 알림입니다.", LauncherText.pushExampleBody),
      (
        "이 iOS 는 화면에 보일 내용(alert)이 없는 알림을 받지 않습니다. 제목이나 본문을 넣으세요.",
        LauncherText.testConditionsMessage(.pushNoVisibleContent)
      ),
      ("기기가 알림 내용을 거절했습니다. JSON 의 aps 값을 확인하세요.", LauncherText.testConditionsMessage(.pushRejected)),
    ])
  }

  private static func problemChecks(_ table: [String: String]) -> [Check] {
    self.pairs(table, [
      ("본문을 넣으세요.", LauncherText.pushProblem(.emptyBody)),
      ("JSON 을 넣으세요.", LauncherText.pushProblem(.empty)),
      ("JSON 형식이 아닙니다. 괄호·따옴표·쉼표를 확인하세요.", LauncherText.pushProblem(.notJSON)),
      ("따옴표가 “ ” 로 바뀌었습니다. 곧은 따옴표(\")로 바꾸세요.", LauncherText.pushProblem(.smartQuotes)),
      ("JSON 의 맨 바깥은 { } 객체여야 합니다.", LauncherText.pushProblem(.rootNotObject)),
      ("JSON 에 aps 키가 있어야 합니다.", LauncherText.pushProblem(.missingAPS)),
      ("aps 값은 { } 객체여야 합니다.", LauncherText.pushProblem(.apsNotObject)),
      ("aps 가 비어 있습니다. alert 같은 값을 넣으세요.", LauncherText.pushProblem(.apsEmpty)),
      ("aps 의 alert 값은 글자나 { } 객체여야 합니다.", LauncherText.pushProblem(.alertInvalid)),
    ])
  }

  /// 보간이 든 키 (표의 값에 인자를 넣은 문구가 코드 결과와 같아야 한다).
  private static func formatChecks(_ table: [String: String]) -> [Check] {
    [
      CatalogTextCatalog.check(table, "%@ (%@)", LauncherText.appPickerName(self.app), "Sample", "com.example.sample"),
      CatalogTextCatalog.check(table, "%@ 권한 바꾸기", LauncherText.privacyMenuAccessibilityLabel(.camera), "카메라"),
      CatalogTextCatalog.check(table, "SimLauncher 가 바꾼 값: %@", LauncherText.privacyHistoryLine(.reset), "다시 묻기 (초기화)"),
      CatalogTextCatalog.check(table, "%lld / %lld 바이트", LauncherText.pushByteCount(120), 120, 4096),
      CatalogTextCatalog.check(
        table,
        "알림 내용이 %lld 바이트입니다. %lld 바이트 이하로 줄이세요.",
        LauncherText.pushProblem(.tooLarge(byteCount: 4097)),
        4097,
        4096
      ),
      CatalogTextCatalog.check(
        table,
        "%@ 앱의 %@ 권한을 바꿨습니다: %@",
        LauncherText.testConditionsResult(.privacyChanged(.microphone, .revoke, appName: "Sample")),
        "Sample",
        "마이크",
        "거부"
      ),
      CatalogTextCatalog.check(
        table, "%@ 앱에 알림을 보냈습니다.", LauncherText.testConditionsResult(.pushSent(appName: "Sample")), "Sample"
      ),
      CatalogTextCatalog.check(
        table,
        "%@ 앱이 알림 권한을 받지 않았거나 기기에 없어 알림을 보일 수 없습니다. 앱에서 알림을 허용한 뒤 다시 보내세요. 앱을 지웠다면 앱 목록 다시 읽기를 누르세요.",
        LauncherText.testConditionsMessage(.pushNotAuthorized(appName: "Sample")),
        "Sample"
      ),
    ]
  }

  /// 표에 키가 있고 값이 키와 같으며 코드 결과가 표의 값과 같은지 보고, 키를 돌려준다.
  static func checkedKeys(in table: [String: String]) -> Set<String> {
    let checks = self.checks(table)
    for check in checks {
      #expect(table[check.key] == check.key, "\(check.key)")
      #expect(check.actual == check.expected, "\(check.key)")
    }
    let keys = Set(checks.map(\.key))
    #expect(keys.count == 56)
    return keys
  }
}

/// 앱 단위 구역 문구 함수가 각 케이스에 돌려주는 값.
struct TestConditionsAppTextTests {
  @Test("앱 단위 구역 문구 56개가 String Catalog 에서 한국어 값으로 컴파일되고, 코드 결과가 표의 값과 같다")
  func textsAreInCompiledKoreanTable() throws {
    let url = try #require(
      Bundle.module.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "ko")
    )
    let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
    #expect(AppConditionsTextCatalog.checkedKeys(in: table).count == 56)
  }

  @Test("권한·푸시 항목 이름은 서비스 이름과 구역 이름이고, 지원 안 함 판정에 들지 않는다")
  func itemNames() {
    #expect(LauncherText.itemName(.privacy(.mediaLibrary)) == "미디어 및 Apple Music")
    #expect(LauncherText.itemName(.push) == "푸시 알림")
    let settings = SimulatorClientFake.defaultDisplaySettings
    #expect(!settings.isUnsupported(.privacy(.camera)))
    #expect(!settings.isUnsupported(.push))
  }

  @Test("권한·푸시 실패 본문은 기존 시트 실패 문구와 같다")
  func failureMessages() {
    #expect(
      LauncherText.testConditionsMessage(.failed(.privacy(.camera), .deviceNotBooted))
        == "기기가 꺼져 있습니다. 기기를 켠 뒤 다시 시도하세요."
    )
    #expect(
      LauncherText.testConditionsMessage(.failed(.push, .commandFailed)) == LauncherText.message(for: .commandFailed)
    )
  }

  @Test("예시 JSON 은 키 골격이 코드 값이고 그대로 보낼 수 있으며, 따옴표가 든 번역 글자도 JSON 을 깨뜨리지 않는다")
  func exampleJSON() throws {
    let json = TestConditionsAppDraft.exampleJSON(title: "제목 \"인용\" / 끝", body: "본문")
    let payload = try PushPayload.json(json).get()
    let object = try #require(JSONSerialization.jsonObject(with: payload.data) as? [String: Any])
    let alert = try #require((object["aps"] as? [String: Any])?["alert"] as? [String: String])
    #expect(alert == ["title": "제목 \"인용\" / 끝", "body": "본문"])
    // 줄바꿈된 예시다 (사람이 고치기 쉽게).
    #expect(json.contains("\n"))
  }
}
