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

/// `simctl privacy` 서비스 (help 목록 + help 에는 없지만 동작하는 `camera`, 실측 Xcode 27.2·iOS 26.5·27.0). rawValue 는 simctl 토큰.
/// 알림(`notifications`)은 simctl 이 바꾸지 못해(exit 1 `Operation not permitted`, 실측) 넣지 않는다. siri·contacts-limited·all 은 쓰지
/// 않는다.
public enum IOSPrivacyService: String, CaseIterable, Hashable, Sendable {
  case location
  case locationAlways = "location-always"
  case camera
  case microphone
  case photos
  case photosAdd = "photos-add"
  case contacts
  case calendar
  case reminders
  case motion
  case mediaLibrary = "media-library"

  /// 바꾸면 실행 중인 앱이 종료된다: `location`·`location-always` 밖의 서비스는 grant·revoke·reset **모두**, 값이 같아도 종료한다
  /// (실측 26.5·27.0: 이미 허용된 camera 를 다시 grant 해도 종료).
  public var terminatesRunningApp: Bool {
    switch self {
    case .location, .locationAlways: false
    case .camera, .microphone, .photos, .photosAdd, .contacts, .calendar, .reminders, .motion, .mediaLibrary: true
    }
  }
}

/// `simctl privacy` 동작. rawValue 는 simctl 토큰. `reset` 은 "아직 묻지 않음" 으로 되돌린다 (앱이 다시 물을 수 있다).
public enum IOSPrivacyAction: String, CaseIterable, Hashable, Sendable {
  case grant
  case revoke
  case reset
}

/// 푸시 보내기 결과. 명령 자체의 실패(꺼짐·없는 기기·Xcode 없음·해석할 수 없는 결과)는 `SimulatorError` 로 던진다.
public enum IOSPushOutcome: Hashable, Sendable {
  /// stdout 에 `Notification sent to '…'` 줄이 있다. iOS 26.5 는 알림 권한이 없는 앱·설치되지 않은 앱에도 이 값이다
  /// (화면에 보이지 않는다, 실측).
  case sent
  /// 앱이 알림 권한을 받지 않았거나 설치되지 않았다: UNErrorDomain 2003 "Source is not authorized" (exit 211, iOS 27.0 실측).
  case notAuthorized
  /// 화면에 보일 내용이 없다: UNErrorDomain 2002 "No content that needs to alert" (exit 210, alert 없는 badge·sound),
  /// 1401 "Notification has no user visible content" (exit 121, content-available) (iOS 27.0 실측).
  case noVisibleContent
  /// simctl 이 payload 형식을 거절했다: NSPOSIXErrorDomain 22(루트가 사전이 아님·aps 없음)·14(aps·alert 형식)·28(4096 바이트 초과).
  /// Core `PushPayload` 검사를 거쳤으면 정상 흐름에서는 나오지 않는다.
  case payloadRejected
}
