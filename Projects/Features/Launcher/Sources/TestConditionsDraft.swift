import Core
import Foundation
import SimulatorInterface

/// 테스트 조건 시트에서 바꾸는 항목. 기기별 "적용 중" 표시(`TestConditionsModel.applying`)와 실패 문구가 어느 항목의 것인지 가른다.
/// TC-B·C 가 앱 단위 항목(권한·푸시·언어)을 케이스로 더한다.
public enum TestConditionItem: Hashable, Sendable {
  case appearance
  case contentSize
  case increaseContrast
  case location
}

/// 마지막 적용이 기기에 반영되지 않은 이유. 다음 적용을 시작하면 지운다.
public enum TestConditionsMessage: Hashable, Sendable {
  /// 명령이 실패했다 (꺼짐·없어짐·Xcode 문제 등).
  case failed(TestConditionItem, SimulatorError)
  /// 쓰기 뒤 다시 읽은 값이 요청과 다르다.
  case notApplied(TestConditionItem)
  /// 쓰기 뒤 다시 읽어 보니 이 기기·iOS 가 그 설정을 지원하지 않는다.
  case unsupported(TestConditionItem)
  /// 이 Xcode 에 고른 위치 시나리오가 없다.
  case scenarioUnavailable
}

/// SimLauncher 가 이 기기에 마지막으로 보낸 위치와 그 시각. 기기에서 지금 위치를 읽을 수 없어 보낸 기록만 보인다.
/// SimLauncher 가 켜져 있는 동안만 기억한다 (저장하지 않는다). 기기를 끄거나 초기화해도 지우지 않는다 (시트가 그렇게 안내한다).
public struct SentLocation: Hashable, Sendable {
  public enum Kind: Hashable, Sendable {
    case point(GeoCoordinate)
    case route(waypointCount: Int, speed: LocationRouteSpeed)
    case scenario(IOSLocationScenario)
    /// 위치 지우기 (경로·시나리오 멈춤 포함).
    case cleared
  }

  public let kind: Kind
  public let sentAt: Date

  public init(kind: Kind, sentAt: Date) {
    self.kind = kind
    self.sentAt = sentAt
  }
}

/// 테스트 조건 시트 초안. 기기는 "테스트 조건…" 을 누른 시점의 값이다. 열 때마다 Model 이 새 번호(`session`)를 붙여, 닫았다
/// 다시 연 뒤 늦게 온 앞 읽기 결과를 버린다. 적용 중 표시는 시트를 닫았다 다시 열어도 이어지도록 Model 의 `applying` 에 있다.
/// 바꾸는 메서드는 Model 만 부른다 (View 는 Model 의 `draft` 를 읽기만 한다).
public struct TestConditionsDraft: Hashable, Sendable {
  /// 화면 구역(외관·글씨 크기·고대비)의 지금 값.
  public enum Display: Hashable, Sendable {
    case loading
    case loaded(IOSDisplaySettings)
    case failed(SimulatorError)
  }

  public let deviceID: VirtualDevice.ID
  /// 시트 제목에 보일 기기 (누른 시점의 이름·런타임 이름).
  public let device: LauncherNotice.Device
  /// 이 시트를 연 번호.
  public let session: Int
  public private(set) var display: Display = .loading
  /// 마지막 적용의 실패·적용 안 됨. 다음 적용을 시작하면 지운다.
  public private(set) var message: TestConditionsMessage?
  /// 한 점 입력란 ("위도, 경도").
  public private(set) var pointText = ""
  /// 경로 입력란 (한 줄에 한 지점).
  public private(set) var routeText = ""
  public private(set) var routeSpeed: LocationRouteSpeed = .walking
  public private(set) var scenario: IOSLocationScenario = .cityRun

  init(deviceID: VirtualDevice.ID, device: LauncherNotice.Device, session: Int) {
    self.deviceID = deviceID
    self.device = device
    self.session = session
  }

  // MARK: - 입력 검사

  /// 한 점 입력을 검사한 좌표. 문제가 있거나 비어 있으면 nil.
  public var pointCoordinate: GeoCoordinate? {
    try? GeoCoordinate.parse(self.pointText).get()
  }

  /// 한 점 입력의 문제. 비어 있으면 문구를 보이지 않으므로 nil (버튼만 꺼진다).
  public var pointProblem: GeoCoordinateProblem? {
    switch GeoCoordinate.parse(self.pointText) {
    case .success, .failure(.empty): nil
    case let .failure(problem): problem
    }
  }

  /// 경로 입력을 검사한 경유지. 문제가 있으면 nil.
  public var routeWaypoints: [GeoCoordinate]? {
    try? LocationRoute.parseWaypoints(self.routeText).get()
  }

  /// 경로 입력의 문제. 공백뿐이면 문구를 보이지 않으므로 nil (버튼만 꺼진다).
  public var routeProblem: LocationRouteProblem? {
    guard !self.routeText.allSatisfy(\.isWhitespace) else { return nil }
    guard case let .failure(problem) = LocationRoute.parseWaypoints(self.routeText) else { return nil }
    return problem
  }

  // MARK: - 바꾸기 (Model 만 부른다)

  mutating func displayStarted() {
    self.display = .loading
  }

  mutating func displayLoaded(_ settings: IOSDisplaySettings) {
    self.display = .loaded(settings)
  }

  mutating func displayFailed(_ error: SimulatorError) {
    self.display = .failed(error)
  }

  /// 적용이 끝나 기기 값이 바뀌었다. 표시가 `.loaded` 일 때만 그 항목을 고친다 (읽는 중이면 다시 읽기가 맞춘다).
  mutating func settingApplied(_ setting: IOSDisplaySetting) {
    guard case var .loaded(settings) = self.display else { return }
    switch setting {
    case let .appearance(value): settings.appearance = .value(value)
    case let .contentSize(value): settings.contentSize = .value(value)
    case let .increaseContrast(value): settings.increaseContrast = .value(value)
    }
    self.display = .loaded(settings)
  }

  /// 적용 뒤 다시 읽은 값. 표시가 `.loaded` 일 때만 바꾼다 (읽는 중이면 다시 읽기가 맞춘다).
  mutating func settingsRead(_ settings: IOSDisplaySettings) {
    guard case .loaded = self.display else { return }
    self.display = .loaded(settings)
  }

  mutating func messageChanged(_ message: TestConditionsMessage?) {
    self.message = message
  }

  mutating func pointTextChanged(_ text: String) {
    self.pointText = text
  }

  mutating func routeTextChanged(_ text: String) {
    self.routeText = text
  }

  mutating func routeSpeedChanged(_ speed: LocationRouteSpeed) {
    self.routeSpeed = speed
  }

  mutating func scenarioChanged(_ scenario: IOSLocationScenario) {
    self.scenario = scenario
  }
}

extension IOSDisplaySetting {
  /// 이 설정이 바꾸는 항목.
  var item: TestConditionItem {
    switch self {
    case .appearance: .appearance
    case .contentSize: .contentSize
    case .increaseContrast: .increaseContrast
    }
  }
}

extension IOSDisplaySettings {
  /// 이 설정을 보낼 수 있다: 그 항목의 지금 값을 읽었고(`.value`) 고른 값과 다르다. 지원 안 함·알 수 없음이면 컨트롤이 꺼진다.
  func canApply(_ setting: IOSDisplaySetting) -> Bool {
    switch setting {
    case let .appearance(value): self.appearance.hasValue(differentFrom: value)
    case let .contentSize(value): self.contentSize.hasValue(differentFrom: value)
    case let .increaseContrast(value): self.increaseContrast.hasValue(differentFrom: value)
    }
  }

  /// 그 항목을 이 기기·iOS 가 지원하지 않는다.
  func isUnsupported(_ item: TestConditionItem) -> Bool {
    switch item {
    case .appearance: self.appearance == .unsupported
    case .contentSize: self.contentSize == .unsupported
    case .increaseContrast: self.increaseContrast == .unsupported
    case .location: false
    }
  }
}

extension IOSSettingReading {
  /// 읽은 값이 있고 그 값이 `other` 와 다르다.
  func hasValue(differentFrom other: Value) -> Bool {
    guard case let .value(current) = self else { return false }
    return current != other
  }
}
