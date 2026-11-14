import Core

/// `cmd uimode night` 의 지금 값.
public enum AndroidNightModeReading: Hashable, Sendable {
  /// `no`
  case light
  /// `yes`
  case dark
  /// `auto`·`custom_schedule`·`custom_bedtime` 등 그 밖의 값 (폴더블 기기의 처음 값이 `custom_bedtime` 이었다, 실측).
  case other
  /// `Night mode:` 줄이 없거나 읽기가 실패했다 (`cmd uimode night` 가 없는 Android 버전 등).
  case unknown
}

/// 테스트 조건 시트가 열 때 읽는 값.
public struct AndroidTestConditions: Hashable, Sendable {
  public var nightMode: AndroidNightModeReading
  /// 기기 위치 서비스 (`cmd location is-location-enabled`). 꺼져 있으면 `emu geo fix` 가 `OK` 여도 앱이 위치를 받지 못한다(실측).
  /// 읽지 못하면 nil.
  public var locationEnabled: Bool?

  public init(nightMode: AndroidNightModeReading, locationEnabled: Bool?) {
    self.nightMode = nightMode
    self.locationEnabled = locationEnabled
  }
}

/// 테스트 조건 쓰기 결과. 명령 자체의 실패(꺼짐·없는 기기·adb 없음)는 `AndroidEmulatorError` 로 던진다.
public enum AndroidConditionOutcome: Hashable, Sendable {
  case applied
  /// 명령은 돌았지만 바뀌지 않았다 (uimode 가 다른 값·`Error:` 로 답함, `emu geo fix` 가 `KO:` 또는 `OK` 없이 답함).
  case notApplied
}
