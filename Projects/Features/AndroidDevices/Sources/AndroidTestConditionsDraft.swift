import AndroidEmulatorInterface
import Core
import Foundation

/// Android 테스트 조건 시트에서 바꾸는 항목. 기기별 "적용 중" 표시와 실패 문구가 어느 항목의 것인지 가른다.
/// TC-B·C 가 앱 단위 항목(권한·언어)을 케이스로 더한다.
public enum AndroidTestConditionItem: Hashable, Sendable {
  case appearance
  case location
}

/// 마지막 적용이 기기에 반영되지 않은 이유. 다음 적용을 시작하면 지운다.
public enum AndroidTestConditionsMessage: Hashable, Sendable {
  /// 명령이 실패했다 (꺼짐·없어짐·adb 문제 등).
  case failed(AndroidTestConditionItem, AndroidEmulatorError)
  /// 명령은 돌았지만 바뀌지 않았다 (uimode 가 다른 값으로 답함, `emu geo fix` 가 `KO:` 로 답함).
  case notApplied(AndroidTestConditionItem)
}

/// SimLauncher 가 이 기기에 마지막으로 보낸 위치(한 점)와 그 시각. 에뮬레이터에서 지금 위치를 읽을 수 없어 보낸 기록만 보인다.
/// SimLauncher 가 켜져 있는 동안만 기억한다 (저장하지 않는다). 기기를 끄거나 초기화해도 지우지 않는다 (시트가 그렇게 안내한다).
public struct AndroidSentLocation: Hashable, Sendable {
  public let coordinate: GeoCoordinate
  public let sentAt: Date

  public init(coordinate: GeoCoordinate, sentAt: Date) {
    self.coordinate = coordinate
    self.sentAt = sentAt
  }
}

/// Android 테스트 조건 시트 초안. 기기는 "테스트 조건…" 을 누른 시점의 값이다. 열 때마다 Model 이 새 번호(`session`)를 붙여,
/// 닫았다 다시 연 뒤 늦게 온 앞 읽기 결과를 버린다. 적용 중 표시는 Model 의 `applying` 에 있다.
/// 바꾸는 메서드는 Model 만 부른다 (View 는 Model 의 `draft` 를 읽기만 한다).
public struct AndroidTestConditionsDraft: Hashable, Sendable {
  /// 시트를 열 때 읽은 값(외관·위치 서비스).
  public enum Conditions: Hashable, Sendable {
    case loading
    case loaded(AndroidTestConditions)
    case failed(AndroidEmulatorError)
  }

  public let deviceID: AndroidVirtualDevice.ID
  /// 시트 제목에 보일 기기 (누른 시점의 이름).
  public let device: AndroidDeviceLabel
  /// 이 시트를 연 번호.
  public let session: Int
  public private(set) var conditions: Conditions = .loading
  /// 마지막 적용의 실패·적용 안 됨. 다음 적용을 시작하면 지운다.
  public private(set) var message: AndroidTestConditionsMessage?
  /// 한 점 입력란 ("위도, 경도").
  public private(set) var pointText = ""

  init(deviceID: AndroidVirtualDevice.ID, device: AndroidDeviceLabel, session: Int) {
    self.deviceID = deviceID
    self.device = device
    self.session = session
  }

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

  /// 기기 위치 서비스가 꺼져 있다고 읽었다 (읽지 못했으면 false: 안내를 보이지 않는다).
  public var isLocationServiceOff: Bool {
    guard case let .loaded(conditions) = self.conditions else { return false }
    return conditions.locationEnabled == false
  }

  // MARK: - 바꾸기 (Model 만 부른다)

  mutating func conditionsStarted() {
    self.conditions = .loading
  }

  mutating func conditionsLoaded(_ conditions: AndroidTestConditions) {
    self.conditions = .loaded(conditions)
  }

  mutating func conditionsFailed(_ error: AndroidEmulatorError) {
    self.conditions = .failed(error)
  }

  /// 외관 적용이 끝나 기기 값이 바뀌었다. 표시가 `.loaded` 일 때만 고친다 (읽는 중이면 다시 읽기가 맞춘다).
  mutating func nightModeApplied(_ appearance: DeviceAppearance) {
    guard case var .loaded(conditions) = self.conditions else { return }
    conditions.nightMode = appearance == .dark ? .dark : .light
    self.conditions = .loaded(conditions)
  }

  mutating func messageChanged(_ message: AndroidTestConditionsMessage?) {
    self.message = message
  }

  mutating func pointTextChanged(_ text: String) {
    self.pointText = text
  }
}

extension AndroidNightModeReading {
  /// 라이트·다크로 읽었으면 그 값. 자동·예약 모드나 읽지 못함이면 nil (그때도 고르면 보낸다: 쓰기 출력으로 확인한다).
  var appearance: DeviceAppearance? {
    switch self {
    case .light: .light
    case .dark: .dark
    case .other, .unknown: nil
    }
  }
}
