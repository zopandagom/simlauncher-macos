import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation

/// 테스트 조건(외관·위치·위치 서비스 켜짐) adb 인자와 출력 해석 (순수). 인자는 모두 고정 토큰이거나 Core 를 거친 숫자라 인용하지 않는다.
/// 켜는 중·끊김 판정은 앱 작업과 같은 `ADBAppCommands.notBooted`.
enum ADBConditionCommands {
  // MARK: - 인자

  /// `Night mode: <값>` 을 찍는다 (`\r` 없이, 실측 API 37).
  static func nightModeReadArguments(serial: String) -> [String] {
    ["-s", serial, "shell", "cmd", "uimode", "night"]
  }

  /// 쓰기도 새 값을 `Night mode: <값>` 으로 찍는다. 대문자(`YES`)는 `Error: mode must be …` (실측).
  static func nightModeWriteArguments(serial: String, appearance: DeviceAppearance) -> [String] {
    ["-s", serial, "shell", "cmd", "uimode", "night", appearance == .dark ? "yes" : "no"]
  }

  /// `emu geo fix <경도> <위도>`: **경도 먼저** (에뮬레이터 콘솔 규칙, 실측). 음수 값도 옵션으로 읽히지 않는다 (실측 `-122.0312 37.3323` → OK).
  static func geoFixArguments(serial: String, coordinate: GeoCoordinate) -> [String] {
    [
      "-s", serial, "emu", "geo", "fix",
      GeoCoordinate.decimalString(coordinate.longitude), GeoCoordinate.decimalString(coordinate.latitude),
    ]
  }

  static func locationEnabledArguments(serial: String) -> [String] {
    ["-s", serial, "shell", "cmd", "location", "is-location-enabled"]
  }

  // MARK: - 출력 해석

  /// 읽기: 종료 코드 0 이고 `Night mode:` 줄이 있으면 그 값(`yes` → `.dark`, `no` → `.light`, 그 밖 → `.other`, 빈 값 → `.unknown`).
  /// 줄이 없으면 켜는 중·끊김 출력은 `.deviceNotBooted`, 그 밖은 `.unknown` (`cmd uimode night` 가 없는 Android 버전일 수 있다, 미실측).
  static func parseNightModeRead(_ result: CommandResult) -> Result<AndroidNightModeReading, AndroidEmulatorError> {
    if result.exitCode == 0, let reading = self.nightModeLine(result) {
      return .success(reading)
    }
    return self.notBooted(result) ? .failure(.deviceNotBooted) : .success(.unknown)
  }

  /// 쓰기: `Night mode:` 줄이 있으면(종료 코드 0) 그 값이 요청과 같을 때 `.applied`, 다르면 `.notApplied`.
  /// 켜는 중·끊김 출력은 `.deviceNotBooted`. `Error:` 로 시작하는 줄이나 0 이 아닌 종료 코드는 `.notApplied` (`Error: mode must be …`
  /// exit 255, 실측). 그 밖(줄 없음)은 nil: 호출한 쪽이 한 번 다시 읽어 판정한다.
  static func parseNightModeWrite(
    _ result: CommandResult,
    requested: DeviceAppearance
  ) -> Result<AndroidConditionOutcome?, AndroidEmulatorError> {
    if self.notBooted(result) {
      return .failure(.deviceNotBooted)
    }
    if result.exitCode == 0, let reading = self.nightModeLine(result) {
      return .success(self.matches(reading, requested) ? .applied : .notApplied)
    }
    let lines = ADBAppCommands.lines(ADBAppCommands.text(result))
    if result.exitCode != 0 || lines.contains(where: { $0.hasPrefix("Error") }) {
      return .success(.notApplied)
    }
    return .success(nil)
  }

  static func matches(_ reading: AndroidNightModeReading, _ requested: DeviceAppearance) -> Bool {
    switch (reading, requested) {
    case (.dark, .dark), (.light, .light): true
    default: false
    }
  }

  /// `emu geo fix` 는 실패해도 exit 0 이다 (실측). 종료 코드 0 이면 stdout 에 `KO:` 로 시작하는 줄 → `.notApplied`,
  /// `OK` 줄 → `.applied`, 둘 다 없으면 `.notApplied` (받아들였는지 모르는 것을 성공으로 보지 않는다).
  /// 0 이 아니면 켜는 중·끊김 출력은 `.deviceNotBooted`, 그 밖 `.adbUnavailable` (`emu` 는 콘솔 연결 실패만 0 이 아니다).
  static func parseGeoFix(_ result: CommandResult) -> Result<AndroidConditionOutcome, AndroidEmulatorError> {
    guard result.exitCode == 0 else {
      return .failure(self.notBooted(result) ? .deviceNotBooted : .adbUnavailable)
    }
    let lines = ADBAppCommands.lines(result.stdout)
    if lines.contains(where: { $0.hasPrefix("KO:") }) {
      return .success(.notApplied)
    }
    return .success(lines.contains("OK") ? .applied : .notApplied)
  }

  /// 종료 코드 0 이고 첫 비지 않은 줄이 `true`/`false` 면 그 값, 그 밖은 nil.
  static func parseLocationEnabled(_ result: CommandResult) -> Bool? {
    guard result.exitCode == 0 else { return nil }
    switch ADBAppCommands.lines(result.stdout).first {
    case "true": return true
    case "false": return false
    default: return nil
    }
  }

  // MARK: - 도우미

  /// stdout 에서 앞 공백을 뺀 줄 머리가 `Night mode:` 인 첫 줄의 값.
  private static func nightModeLine(_ result: CommandResult) -> AndroidNightModeReading? {
    guard let line = ADBAppCommands.lines(result.stdout).first(where: { $0.hasPrefix("Night mode:") }) else {
      return nil
    }
    switch line.dropFirst("Night mode:".count).trimmingCharacters(in: .whitespaces) {
    case "yes": return .dark
    case "no": return .light
    case "": return .unknown
    default: return .other
    }
  }

  private static func notBooted(_ result: CommandResult) -> Bool {
    ADBAppCommands.notBooted(ADBAppCommands.lines(ADBAppCommands.text(result)))
  }
}
