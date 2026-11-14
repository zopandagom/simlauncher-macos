import Core

/// iOS 글씨 크기 (`simctl ui <기기> content_size`). rawValue 는 simctl 쓰기 토큰, 순서는 작은 것부터.
/// 읽기 값은 대소문자가 다를 수 있다 (`extra-small` 을 쓰면 `extra-Small`, `small` 을 쓰면 `Small`, 실측 Xcode 27.2·iOS 27.0).
public enum IOSContentSize: String, CaseIterable, Hashable, Sendable {
  case extraSmall = "extra-small"
  case small
  case medium
  case large
  case extraLarge = "extra-large"
  case extraExtraLarge = "extra-extra-large"
  case extraExtraExtraLarge = "extra-extra-extra-large"
  case accessibilityMedium = "accessibility-medium"
  case accessibilityLarge = "accessibility-large"
  case accessibilityExtraLarge = "accessibility-extra-large"
  case accessibilityExtraExtraLarge = "accessibility-extra-extra-large"
  case accessibilityExtraExtraExtraLarge = "accessibility-extra-extra-extra-large"
}

/// `simctl ui` 읽기 한 항목.
public enum IOSSettingReading<Value: Hashable & Sendable>: Hashable, Sendable {
  case value(Value)
  /// simctl 이 `unsupported` 로 답했다 (이 기기·iOS 가 지원하지 않음).
  case unsupported
  /// `unknown`·빈 값·모르는 값 (꺼진 기기는 셋 다 `unknown`, exit 0).
  case unknown
}

/// 화면 설정 세 가지의 지금 값.
public struct IOSDisplaySettings: Hashable, Sendable {
  public var appearance: IOSSettingReading<DeviceAppearance>
  public var contentSize: IOSSettingReading<IOSContentSize>
  /// 고대비 (`increase_contrast`): `enabled` → true, `disabled` → false.
  public var increaseContrast: IOSSettingReading<Bool>

  public init(
    appearance: IOSSettingReading<DeviceAppearance>,
    contentSize: IOSSettingReading<IOSContentSize>,
    increaseContrast: IOSSettingReading<Bool>
  ) {
    self.appearance = appearance
    self.contentSize = contentSize
    self.increaseContrast = increaseContrast
  }
}

/// 바꿀 화면 설정 하나.
public enum IOSDisplaySetting: Hashable, Sendable {
  case appearance(DeviceAppearance)
  case contentSize(IOSContentSize)
  case increaseContrast(Bool)
}

/// 화면 설정 쓰기 결과. 명령 자체의 실패(꺼짐·없는 기기·Xcode 없음)는 `SimulatorError` 로 던진다.
public enum IOSDisplaySettingOutcome: Hashable, Sendable {
  /// 쓴 뒤 다시 읽은 값이 요청과 같다.
  case applied
  /// 쓰기 뒤 다시 읽은 값이 요청과 다르다 (exit 0 `Invalid argument` 포함). 읽은 값을 담는다
  /// (그 항목이 `.unsupported` 면 이 기기·iOS 가 지원하지 않음).
  case notApplied(IOSDisplaySettings)
}

/// `simctl location run` 의 기본 시나리오 (`simctl location list`, Xcode 27.2). rawValue 는 simctl 이름 그대로(대소문자 구분).
public enum IOSLocationScenario: String, CaseIterable, Hashable, Sendable {
  case cityRun = "City Run"
  case cityBicycleRide = "City Bicycle Ride"
  case freewayDrive = "Freeway Drive"
  /// 몇 초 움직인 뒤 쿠퍼티노 Apple 에 멈추는 고정 위치 (실측).
  case apple = "Apple"
}

/// 위치 시뮬레이션 하나. 경로·시나리오는 simctl 이 끝난 뒤에도 기기 안에서 이어지고, `clear`·다른 위치·기기 끄기로 멈춘다 (실측).
public enum IOSLocationSimulation: Hashable, Sendable {
  case point(GeoCoordinate)
  case route(LocationRoute)
  case scenario(IOSLocationScenario)
  /// 위치를 지운다 (진행 중인 경로·시나리오도 멈춘다).
  case clear
}

/// 위치 시뮬레이션 결과. simctl 이 받아들였는지(위치가 바뀌었는지)는 읽을 방법이 없어 확인하지 않는다.
public enum IOSLocationOutcome: Hashable, Sendable {
  case applied
  /// 이 Xcode 에 그 시나리오가 없다 (`Could not find scenario`).
  case scenarioUnavailable
}
