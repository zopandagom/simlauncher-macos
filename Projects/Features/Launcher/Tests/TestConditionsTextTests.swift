import Core
import Foundation
import SimulatorInterface
import Testing
@testable import LauncherFeature

/// 테스트 조건 문구(`LauncherText+TestConditions.swift`)의 String Catalog 키. `LauncherResourcesTests` 가 컴파일된 표로 모든 키를
/// 본다. "(공통)" 키는 Android 기기 목록의 `LauncherTextSyncTests` 가 Launcher 원본 카탈로그로 다시 본다.
enum TestConditionsTextCatalog {
  typealias Check = CatalogTextCatalog.Check

  static let device = LauncherNotice.Device(name: "iPhone 17", runtimeName: "iOS 26.0")
  static let sentAt = Date(timeIntervalSince1970: 1_800_000_000)
  static var sentTime: String {
    sentAt.formatted(date: .omitted, time: .standard)
  }

  static func checks(_ table: [String: String]) -> [Check] {
    self.plainChecks(table) + self.choiceChecks(table) + self.formatChecks(table)
  }

  /// 보간 없는 키.
  private static func plainChecks(_ table: [String: String]) -> [Check] {
    let pairs: [(String, String)] = [
      ("테스트 조건…", LauncherText.testConditionsButton),
      ("외관·글씨 크기·위치 같은 테스트 조건을 바꿉니다.", LauncherText.testConditionsHelp),
      ("켜진 기기에서만 바꿀 수 있습니다.", LauncherText.testConditionsBootedOnlyHelp),
      ("바꾼 조건은 기기에 바로 적용되고, 시트를 닫거나 SimLauncher 를 꺼도 기기에 남습니다.", LauncherText.testConditionsSheetNote),
      ("화면", LauncherText.displaySection),
      ("외관", LauncherText.appearanceLabel),
      ("라이트", LauncherText.appearanceName(.light)),
      ("다크", LauncherText.appearanceName(.dark)),
      ("글씨 크기", LauncherText.contentSizeLabel),
      ("고대비", LauncherText.increaseContrastLabel),
      ("지금 값을 읽는 중…", LauncherText.readingConditions),
      ("지금 값을 읽지 못했습니다.", LauncherText.conditionsReadFailed),
      ("다시 읽기", LauncherText.rereadButton),
      ("이 iOS 버전은 이 설정을 지원하지 않습니다.", LauncherText.settingUnsupported),
      ("지금 값을 알 수 없습니다.", LauncherText.settingUnknown),
      ("적용하는 중…", LauncherText.applyingCondition),
      ("위치", LauncherText.locationSection),
      ("위도, 경도", LauncherText.coordinateField),
      ("예: 37.5665, 126.9780", LauncherText.coordinatePlaceholder),
      ("자주 쓰는 위치", LauncherText.locationPresetsMenu),
      ("이 위치로 설정", LauncherText.setPointButton),
      ("경로", LauncherText.routeLabel),
      ("한 줄에 한 지점씩 위도, 경도를 넣으세요 (2~100개).", LauncherText.routeGuide),
      ("속도", LauncherText.routeSpeedLabel),
      ("경로 시작", LauncherText.startRouteButton),
      ("시나리오", LauncherText.scenarioLabel),
      ("시나리오 실행", LauncherText.runScenarioButton),
      ("위치 지우기", LauncherText.clearLocationButton),
      ("진행 중인 경로·시나리오를 멈추고 시뮬레이션한 위치를 지웁니다.", LauncherText.clearLocationHelp),
      (
        "경로·시나리오는 기기 안에서 계속 움직입니다. 멈추려면 위치 지우기를 누르거나 다른 위치를 설정하세요. 기기를 끄면 멈춥니다.",
        LauncherText.locationPlaybackNote
      ),
      ("위치 지움", LauncherText.sentLocationContent(.cleared)),
      (
        "기기에서 지금 위치를 읽을 수 없어 SimLauncher 가 보낸 기록만 보입니다. 다른 도구로 바꾸면 달라질 수 있습니다.",
        LauncherText.sentLocationNote
      ),
      ("기기를 끄거나 초기화해도 이 기록은 남습니다.", LauncherText.sentLocationKeptNote),
      ("위도, 경도를 숫자로 넣으세요. 소수점은 마침표(.)입니다.", LauncherText.coordinateProblem(.format)),
      ("위도는 -90 에서 90 사이여야 합니다.", LauncherText.coordinateProblem(.latitudeOutOfRange)),
      ("경도는 -180 에서 180 사이여야 합니다.", LauncherText.coordinateProblem(.longitudeOutOfRange)),
      ("지점을 2개 이상 넣으세요.", LauncherText.routeProblem(.tooFewWaypoints)),
      ("지점은 100개까지 넣을 수 있습니다.", LauncherText.routeProblem(.tooManyWaypoints)),
      ("이 Xcode 에는 이 시나리오가 없습니다. 다른 시나리오나 경로를 쓰세요.", LauncherText.testConditionsMessage(.scenarioUnavailable)),
      ("기기가 꺼져 있습니다. 기기를 켠 뒤 다시 시도하세요.", LauncherText.testConditionsFailure(.deviceNotBooted)),
      ("기기를 찾지 못했습니다. 목록을 새로 고친 뒤 다시 시도하세요.", LauncherText.testConditionsFailure(.deviceNotFound)),
    ]
    return pairs.map { CatalogTextCatalog.check(table, $0.0, $0.1) }
  }

  /// 고르는 값의 이름 (글씨 크기·프리셋·속도·시나리오).
  private static func choiceChecks(_ table: [String: String]) -> [Check] {
    var pairs: [(String, String)] = []
    let sizes = [
      "아주 작게", "작게", "조금 작게", "기본", "조금 크게", "크게", "아주 크게",
      "손쉬운 사용 1", "손쉬운 사용 2", "손쉬운 사용 3", "손쉬운 사용 4", "손쉬운 사용 5",
    ]
    pairs += zip(sizes, IOSContentSize.allCases.map(LauncherText.contentSizeName)).map { ($0, $1) }
    let presets = ["서울", "도쿄", "쿠퍼티노", "뉴욕", "런던", "시드니"]
    pairs += zip(presets, LocationPreset.allCases.map(LauncherText.presetName)).map { ($0, $1) }
    let speeds = ["걷기", "달리기", "자전거", "자동차", "고속도로"]
    pairs += zip(speeds, LocationRouteSpeed.allCases.map(LauncherText.routeSpeedName)).map { ($0, $1) }
    let scenarios = ["도시 달리기", "도시 자전거", "고속도로 주행", "Apple 본사 (고정 위치)"]
    pairs += zip(scenarios, IOSLocationScenario.allCases.map(LauncherText.scenarioName)).map { ($0, $1) }
    return pairs.map { CatalogTextCatalog.check(table, $0.0, $0.1) }
  }

  /// 보간이 든 키 (표의 값에 인자를 넣은 문구가 코드 결과와 같아야 한다).
  private static func formatChecks(_ table: [String: String]) -> [Check] {
    let point = GeoCoordinate(latitude: -33.8688, longitude: 151.2093)!
    let pointText = LauncherText.sentLocationContent(.point(point))
    let routeContent = LauncherText.sentLocationContent(.route(waypointCount: 3, speed: .driving))
    let line = LauncherText.coordinateProblem(.longitudeOutOfRange)
    return [
      CatalogTextCatalog.check(
        table,
        "%@ 테스트 조건",
        LauncherText.testConditionsSheetTitle(for: self.device),
        "iPhone 17"
      ),
      CatalogTextCatalog.check(table, "%@, %@", pointText, "-33.8688", "151.2093"),
      CatalogTextCatalog.check(table, "경로 %lld개 지점 · %@", routeContent, 3, "자동차"),
      CatalogTextCatalog.check(
        table, "시나리오 %@", LauncherText.sentLocationContent(.scenario(.apple)), "Apple 본사 (고정 위치)"
      ),
      CatalogTextCatalog.check(
        table,
        "SimLauncher 가 마지막으로 보낸 위치 (%@): %@",
        LauncherText.sentLocationLine(SentLocation(kind: .point(point), sentAt: self.sentAt)),
        self.sentTime,
        pointText
      ),
      CatalogTextCatalog.check(
        table,
        "%lld번째 줄: %@",
        LauncherText.routeProblem(.line(number: 4, .longitudeOutOfRange)),
        4,
        line
      ),
      CatalogTextCatalog.check(
        table,
        "%@ 설정이 적용되지 않았습니다. 기기를 다시 켠 뒤 시도하세요.",
        LauncherText.testConditionsMessage(.notApplied(.contentSize)),
        "글씨 크기"
      ),
      CatalogTextCatalog.check(
        table,
        "이 iOS 버전은 %@ 설정을 지원하지 않습니다.",
        LauncherText.testConditionsMessage(.unsupported(.increaseContrast)),
        "고대비"
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
    #expect(keys.count == 76)
    return keys
  }
}

/// 테스트 조건 문구 함수가 각 케이스에 돌려주는 값.
struct TestConditionsTextTests {
  @Test("테스트 조건 문구 76개가 String Catalog 에서 한국어 값으로 컴파일되고, 코드 결과가 표의 값과 같다")
  func textsAreInCompiledKoreanTable() throws {
    let url = try #require(
      Bundle.module.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "ko")
    )
    let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
    #expect(TestConditionsTextCatalog.checkedKeys(in: table).count == 76)
  }

  @Test("적용 실패 본문: 꺼짐·없어짐은 시트 문구, 그 밖은 기존 시뮬레이터 오류 문구")
  func failureMessages() {
    #expect(
      LauncherText.testConditionsMessage(.failed(.appearance, .deviceNotBooted))
        == "기기가 꺼져 있습니다. 기기를 켠 뒤 다시 시도하세요."
    )
    #expect(
      LauncherText.testConditionsMessage(.failed(.location, .deviceNotFound))
        == "기기를 찾지 못했습니다. 목록을 새로 고친 뒤 다시 시도하세요."
    )
    for error in [SimulatorError.developerToolsUnavailable, .commandFailed, .unexpectedOutput] {
      #expect(LauncherText.testConditionsFailure(error) == LauncherText.message(for: error))
    }
  }

  @Test("적용 안 됨·지원 안 함 문구에 항목 이름이 들어간다")
  func notAppliedNamesItem() {
    #expect(
      LauncherText.testConditionsMessage(.notApplied(.appearance)) == "외관 설정이 적용되지 않았습니다. 기기를 다시 켠 뒤 시도하세요."
    )
    #expect(LauncherText.testConditionsMessage(.unsupported(.contentSize)) == "이 iOS 버전은 글씨 크기 설정을 지원하지 않습니다.")
    #expect(LauncherText.itemName(.location) == "위치")
  }

  @Test("빈 좌표 문제도 형식 문구를 돌려준다 (화면은 빈 입력에 문구를 보이지 않는다)")
  func emptyProblemText() {
    #expect(LauncherText.coordinateProblem(.empty) == LauncherText.coordinateProblem(.format))
    #expect(LauncherText.routeProblem(.line(number: 1, .empty)) == "1번째 줄: 위도, 경도를 숫자로 넣으세요. 소수점은 마침표(.)입니다.")
  }

  @Test("좌표 글자는 로캘과 관계없이 마침표 소수점이다")
  func coordinateTextUsesPeriod() throws {
    let coordinate = try #require(GeoCoordinate(latitude: 37.5665, longitude: -122.031219))
    #expect(LauncherText.coordinateText(coordinate) == "37.5665, -122.031219")
  }
}
