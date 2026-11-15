import Core

/// `cmd uimode night` 의 지금 값.
public enum AndroidNightModeReading: Hashable, Sendable {
  /// `no`
  case light
  /// `yes`
  case dark
  /// `auto`·`custom_schedule`·`custom_bedtime` 등 그 밖의 값 (폴더블 기기의 처음 값이 `custom_bedtime` 이었다, 실측).
  case other
  /// `Night mode:` 줄이 없거나 값이 비었거나 읽기가 실패했다(종료 코드가 0 이 아님 포함. `cmd uimode night` 가 없는 Android 버전 등).
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
  /// 명령은 돌았지만 바뀌지 않았다 (uimode 가 다른 값으로 답함·`Error` 로 시작하는 줄·0 이 아닌 종료 코드,
  /// `emu geo fix` 가 `KO:` 줄로 답하거나 `OK` 줄이 없음).
  case notApplied
}

/// 런타임 권한 이름 (`android.permission.CAMERA`). 기기 출력(`dumpsys package`)에서 읽은 값이 adb 셸 인자로 가므로 형식을 검사한 값만
/// 만든다: 1~255자, 비지 않은 ASCII 영숫자·`_` 조각을 `.` 로 이은 2조각 이상. 아니면 nil.
public struct AndroidRuntimePermission: Hashable, Sendable, Comparable {
  public static let maxLength = 255

  public let rawValue: String

  public init?(_ rawValue: String) {
    guard (1 ... Self.maxLength).contains(rawValue.unicodeScalars.count) else {
      return nil
    }
    let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)
    guard components.count >= 2, components.allSatisfy(Self.isValidComponent) else {
      return nil
    }
    self.rawValue = rawValue
  }

  /// 비지 않고 ASCII 영숫자·`_` 만.
  private static func isValidComponent(_ component: Substring) -> Bool {
    !component.isEmpty && component.unicodeScalars.allSatisfy { scalar in
      scalar == "_" || ("a" ... "z").contains(scalar) || ("A" ... "Z").contains(scalar)
        || ("0" ... "9").contains(scalar)
    }
  }

  public static func < (lhs: AndroidRuntimePermission, rhs: AndroidRuntimePermission) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// 앱 하나의 런타임 권한 하나와 지금 상태 (`dumpsys package` 의 `runtime permissions:` 블록 줄 `<이름>: granted=<true|false>`).
public struct AndroidPermissionGrant: Hashable, Sendable {
  public let permission: AndroidRuntimePermission
  public let isGranted: Bool

  public init(permission: AndroidRuntimePermission, isGranted: Bool) {
    self.permission = permission
    self.isGranted = isGranted
  }
}

/// 앱 하나의 런타임 권한 읽기 결과.
public enum AndroidAppPermissions: Hashable, Sendable {
  /// user 0 의 `runtime permissions:` 블록 순서 그대로. 비면 바꿀 수 있는 권한을 요청하지 않는 앱.
  case runtime([AndroidPermissionGrant])
  /// 앱이 기기에 없다 (`dumpsys package` 의 `Unable to find package: <패키지>` 줄, exit 0, 실측).
  case appNotInstalled
}

/// 런타임 권한 쓰기 결과. 명령 자체의 실패(꺼짐·없는 기기·adb 없음)는 `AndroidEmulatorError` 로 던진다.
public enum AndroidPermissionOutcome: Hashable, Sendable {
  /// 쓴 뒤 다시 읽은 상태에서 그 권한이 요청 값이다. 다시 읽은 목록 전체를 담는다.
  case applied([AndroidPermissionGrant])
  /// 명령은 돌았는데 다시 읽은 상태가 요청 값이 아니거나 그 권한이 목록에 없다. 다시 읽은 목록 전체를 담는다
  /// (앱이 선언하지 않은 권한은 출력 없이 exit 0, 바꿀 수 없는 권한은 exit 255 `SecurityException`, 없는 권한은 exit 255
  /// `IllegalArgumentException`, 실측 API 37).
  case notApplied([AndroidPermissionGrant])
  /// 앱이 기기에 없다: 쓰기(`pm grant`·`pm revoke`)의 `Failure [package not found]`·
  /// `Error: package not found` 줄(exit 1, 실측) 또는 다시 읽기의 `AndroidAppPermissions.appNotInstalled`.
  case appNotInstalled
}
