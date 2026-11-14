import Core
import Foundation
import SimulatorInterface

/// 테스트 조건("테스트 조건…" 시트) 문구. 키는 다른 문구와 같은 `Localizable.xcstrings` 에 있다. "(공통)" 문구는 Android 기기
/// 목록(AndroidDevices)에도 같은 키·값으로 있다 (그쪽 `LauncherTextSyncTests` 가 확인한다).
extension LauncherText {
  // MARK: - 기기 행

  /// (공통)
  static var testConditionsButton: String {
    String(localized: "테스트 조건…", bundle: .module)
  }

  static var testConditionsHelp: String {
    String(localized: "외관·글씨 크기·위치 같은 테스트 조건을 바꿉니다.", bundle: .module)
  }

  /// (공통) 꺼짐·켜는 중·쓸 수 없는 기기의 버튼 툴팁.
  static var testConditionsBootedOnlyHelp: String {
    String(localized: "켜진 기기에서만 바꿀 수 있습니다.", bundle: .module)
  }

  // MARK: - 시트

  /// (공통) 시트 제목. 기기 이름은 번역하지 않는 값이다.
  static func testConditionsSheetTitle(for device: LauncherNotice.Device) -> String {
    String(localized: "\(device.name) 테스트 조건", bundle: .module)
  }

  /// (공통)
  static var testConditionsSheetNote: String {
    String(localized: "바꾼 조건은 기기에 바로 적용되고, 시트를 닫거나 SimLauncher 를 꺼도 기기에 남습니다.", bundle: .module)
  }

  /// (공통)
  static var displaySection: String {
    String(localized: "화면", bundle: .module)
  }

  /// (공통)
  static var appearanceLabel: String {
    String(localized: "외관", bundle: .module)
  }

  /// (공통)
  static func appearanceName(_ appearance: DeviceAppearance) -> String {
    switch appearance {
    case .light: String(localized: "라이트", bundle: .module)
    case .dark: String(localized: "다크", bundle: .module)
    }
  }

  static var contentSizeLabel: String {
    String(localized: "글씨 크기", bundle: .module)
  }

  static var increaseContrastLabel: String {
    String(localized: "고대비", bundle: .module)
  }

  /// 글씨 크기 12단계 (작은 것부터). 손쉬운 사용 5단계는 `accessibilitySizeName(_:)` 이 고른다.
  static func contentSizeName(_ size: IOSContentSize) -> String {
    switch size {
    case .extraSmall: String(localized: "아주 작게", bundle: .module)
    case .small: String(localized: "작게", bundle: .module)
    case .medium: String(localized: "조금 작게", bundle: .module)
    case .large: String(localized: "기본", bundle: .module)
    case .extraLarge: String(localized: "조금 크게", bundle: .module)
    case .extraExtraLarge: String(localized: "크게", bundle: .module)
    case .extraExtraExtraLarge: String(localized: "아주 크게", bundle: .module)
    case .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge, .accessibilityExtraExtraLarge,
         .accessibilityExtraExtraExtraLarge:
      self.accessibilitySizeName(size)
    }
  }

  /// 손쉬운 사용 글씨 크기 5단계 (`contentSizeName(_:)` 가 부른다. 그 밖의 크기는 그쪽 이름으로 돌려보낸다).
  private static func accessibilitySizeName(_ size: IOSContentSize) -> String {
    switch size {
    case .accessibilityMedium: String(localized: "손쉬운 사용 1", bundle: .module)
    case .accessibilityLarge: String(localized: "손쉬운 사용 2", bundle: .module)
    case .accessibilityExtraLarge: String(localized: "손쉬운 사용 3", bundle: .module)
    case .accessibilityExtraExtraLarge: String(localized: "손쉬운 사용 4", bundle: .module)
    case .accessibilityExtraExtraExtraLarge: String(localized: "손쉬운 사용 5", bundle: .module)
    case .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge:
      self.contentSizeName(size)
    }
  }

  /// (공통)
  static var readingConditions: String {
    String(localized: "지금 값을 읽는 중…", bundle: .module)
  }

  /// (공통)
  static var conditionsReadFailed: String {
    String(localized: "지금 값을 읽지 못했습니다.", bundle: .module)
  }

  /// (공통)
  static var rereadButton: String {
    String(localized: "다시 읽기", bundle: .module)
  }

  static var settingUnsupported: String {
    String(localized: "이 iOS 버전은 이 설정을 지원하지 않습니다.", bundle: .module)
  }

  static var settingUnknown: String {
    String(localized: "지금 값을 알 수 없습니다.", bundle: .module)
  }

  /// (공통)
  static var applyingCondition: String {
    String(localized: "적용하는 중…", bundle: .module)
  }

  // MARK: - 위치

  /// (공통)
  static var locationSection: String {
    String(localized: "위치", bundle: .module)
  }

  /// (공통)
  static var coordinateField: String {
    String(localized: "위도, 경도", bundle: .module)
  }

  /// (공통)
  static var coordinatePlaceholder: String {
    String(localized: "예: 37.5665, 126.9780", bundle: .module)
  }

  /// (공통)
  static var locationPresetsMenu: String {
    String(localized: "자주 쓰는 위치", bundle: .module)
  }

  /// (공통)
  static func presetName(_ preset: LocationPreset) -> String {
    switch preset {
    case .seoul: String(localized: "서울", bundle: .module)
    case .tokyo: String(localized: "도쿄", bundle: .module)
    case .cupertino: String(localized: "쿠퍼티노", bundle: .module)
    case .newYork: String(localized: "뉴욕", bundle: .module)
    case .london: String(localized: "런던", bundle: .module)
    case .sydney: String(localized: "시드니", bundle: .module)
    }
  }

  /// (공통)
  static var setPointButton: String {
    String(localized: "이 위치로 설정", bundle: .module)
  }

  static var routeLabel: String {
    String(localized: "경로", bundle: .module)
  }

  static var routeGuide: String {
    String(localized: "한 줄에 한 지점씩 위도, 경도를 넣으세요 (2~100개).", bundle: .module)
  }

  static var routeSpeedLabel: String {
    String(localized: "속도", bundle: .module)
  }

  static func routeSpeedName(_ speed: LocationRouteSpeed) -> String {
    switch speed {
    case .walking: String(localized: "걷기", bundle: .module)
    case .running: String(localized: "달리기", bundle: .module)
    case .cycling: String(localized: "자전거", bundle: .module)
    case .driving: String(localized: "자동차", bundle: .module)
    case .highway: String(localized: "고속도로", bundle: .module)
    }
  }

  static var startRouteButton: String {
    String(localized: "경로 시작", bundle: .module)
  }

  static var scenarioLabel: String {
    String(localized: "시나리오", bundle: .module)
  }

  static func scenarioName(_ scenario: IOSLocationScenario) -> String {
    switch scenario {
    case .cityRun: String(localized: "도시 달리기", bundle: .module)
    case .cityBicycleRide: String(localized: "도시 자전거", bundle: .module)
    case .freewayDrive: String(localized: "고속도로 주행", bundle: .module)
    case .apple: String(localized: "Apple 본사 (고정 위치)", bundle: .module)
    }
  }

  static var runScenarioButton: String {
    String(localized: "시나리오 실행", bundle: .module)
  }

  static var clearLocationButton: String {
    String(localized: "위치 지우기", bundle: .module)
  }

  static var clearLocationHelp: String {
    String(localized: "진행 중인 경로·시나리오를 멈추고 시뮬레이션한 위치를 지웁니다.", bundle: .module)
  }

  static var locationPlaybackNote: String {
    String(
      localized: "경로·시나리오는 기기 안에서 계속 움직입니다. 멈추려면 위치 지우기를 누르거나 다른 위치를 설정하세요. 기기를 끄면 멈춥니다.",
      bundle: .module
    )
  }

  /// (공통) 마지막으로 보낸 위치 줄. 시각과 내용.
  static func sentLocationLine(_ sent: SentLocation) -> String {
    let time = sent.sentAt.formatted(date: .omitted, time: .standard)
    let content = self.sentLocationContent(sent.kind)
    return String(localized: "SimLauncher 가 마지막으로 보낸 위치 (\(time)): \(content)", bundle: .module)
  }

  static func sentLocationContent(_ kind: SentLocation.Kind) -> String {
    switch kind {
    case let .point(coordinate):
      self.coordinateText(coordinate)
    case let .route(count, speed):
      String(localized: "경로 \(count)개 지점 · \(self.routeSpeedName(speed))", bundle: .module)
    case let .scenario(scenario):
      String(localized: "시나리오 \(self.scenarioName(scenario))", bundle: .module)
    case .cleared:
      String(localized: "위치 지움", bundle: .module)
    }
  }

  /// (공통) 위도, 경도. 숫자는 로캘과 관계없이 마침표 소수점이다 (입력란과 같은 형식).
  static func coordinateText(_ coordinate: GeoCoordinate) -> String {
    let latitude = GeoCoordinate.decimalString(coordinate.latitude)
    let longitude = GeoCoordinate.decimalString(coordinate.longitude)
    return String(localized: "\(latitude), \(longitude)", bundle: .module)
  }

  /// (공통)
  static var sentLocationNote: String {
    String(
      localized: "기기에서 지금 위치를 읽을 수 없어 SimLauncher 가 보낸 기록만 보입니다. 다른 도구로 바꾸면 달라질 수 있습니다.",
      bundle: .module
    )
  }

  /// (공통) 기록은 기기를 끄거나 초기화해도 지우지 않는다.
  static var sentLocationKeptNote: String {
    String(localized: "기기를 끄거나 초기화해도 이 기록은 남습니다.", bundle: .module)
  }

  /// (공통) 좌표 입력 문제. 빈 입력은 문구를 보이지 않는다 (호출하지 않는다).
  static func coordinateProblem(_ problem: GeoCoordinateProblem) -> String {
    switch problem {
    case .empty, .format:
      String(localized: "위도, 경도를 숫자로 넣으세요. 소수점은 마침표(.)입니다.", bundle: .module)
    case .latitudeOutOfRange:
      String(localized: "위도는 -90 에서 90 사이여야 합니다.", bundle: .module)
    case .longitudeOutOfRange:
      String(localized: "경도는 -180 에서 180 사이여야 합니다.", bundle: .module)
    }
  }

  static func routeProblem(_ problem: LocationRouteProblem) -> String {
    switch problem {
    case let .line(number, problem):
      String(localized: "\(number)번째 줄: \(self.coordinateProblem(problem))", bundle: .module)
    case .tooFewWaypoints:
      String(localized: "지점을 2개 이상 넣으세요.", bundle: .module)
    case .tooManyWaypoints:
      String(localized: "지점은 100개까지 넣을 수 있습니다.", bundle: .module)
    }
  }

  // MARK: - 실패·적용 안 됨

  /// 적용 실패·적용 안 됨 줄.
  static func testConditionsMessage(_ message: TestConditionsMessage) -> String {
    switch message {
    case let .failed(_, error):
      self.testConditionsFailure(error)
    case let .notApplied(item):
      String(localized: "\(self.itemName(item)) 설정이 적용되지 않았습니다. 기기를 다시 켠 뒤 시도하세요.", bundle: .module)
    case let .unsupported(item):
      String(localized: "이 iOS 버전은 \(self.itemName(item)) 설정을 지원하지 않습니다.", bundle: .module)
    case .scenarioUnavailable:
      String(localized: "이 Xcode 에는 이 시나리오가 없습니다. 다른 시나리오나 경로를 쓰세요.", bundle: .module)
    }
  }

  /// 읽기·적용 실패 본문. 꺼짐·없어짐은 이 시트의 문구, 그 밖은 기존 시뮬레이터 오류 문구.
  static func testConditionsFailure(_ error: SimulatorError) -> String {
    switch error {
    case .deviceNotBooted:
      String(localized: "기기가 꺼져 있습니다. 기기를 켠 뒤 다시 시도하세요.", bundle: .module)
    case .deviceNotFound:
      String(localized: "기기를 찾지 못했습니다. 목록을 새로 고친 뒤 다시 시도하세요.", bundle: .module)
    default:
      self.message(for: error)
    }
  }

  /// 항목 이름 (적용 안 됨 문구에 넣는다).
  static func itemName(_ item: TestConditionItem) -> String {
    switch item {
    case .appearance: self.appearanceLabel
    case .contentSize: self.contentSizeLabel
    case .increaseContrast: self.increaseContrastLabel
    case .location: self.locationSection
    }
  }
}
