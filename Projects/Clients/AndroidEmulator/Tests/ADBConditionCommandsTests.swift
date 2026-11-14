import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation
import Testing
@testable import AndroidEmulatorImpl

/// 테스트 조건 adb 인자(정확한 배열)와 출력 해석. 기대 배열은 실제 기기로 확인한 명령이다 (API 37).
struct ADBConditionCommandsTests {
  private static let serial = "emulator-5554"

  private static func result(_ code: Int32, stdout: String = "", stderr: String = "") -> CommandResult {
    CommandResult(exitCode: code, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8))
  }

  @Test("인자: uimode 읽기·쓰기, geo fix 는 경도 먼저, 위치 서비스 읽기")
  func arguments() throws {
    #expect(
      ADBConditionCommands.nightModeReadArguments(serial: Self.serial)
        == ["-s", "emulator-5554", "shell", "cmd", "uimode", "night"]
    )
    #expect(
      ADBConditionCommands.nightModeWriteArguments(serial: Self.serial, appearance: .dark)
        == ["-s", "emulator-5554", "shell", "cmd", "uimode", "night", "yes"]
    )
    #expect(
      ADBConditionCommands.nightModeWriteArguments(serial: Self.serial, appearance: .light)
        == ["-s", "emulator-5554", "shell", "cmd", "uimode", "night", "no"]
    )
    let coordinate = try #require(GeoCoordinate(latitude: 37.3323, longitude: -122.0312))
    #expect(
      ADBConditionCommands.geoFixArguments(serial: Self.serial, coordinate: coordinate)
        == ["-s", "emulator-5554", "emu", "geo", "fix", "-122.0312", "37.3323"]
    )
    #expect(
      ADBConditionCommands.locationEnabledArguments(serial: Self.serial)
        == ["-s", "emulator-5554", "shell", "cmd", "location", "is-location-enabled"]
    )
  }

  @Test(
    "uimode 읽기",
    arguments: [
      ("Night mode: no\n", AndroidNightModeReading.light),
      ("Night mode: yes\r\n", .dark),
      ("Night mode: custom_bedtime\n", .other),
      ("Night mode: auto", .other),
      ("Night mode:\n", .unknown),
      ("", .unknown),
      ("something else\n", .unknown),
    ]
  )
  func nightModeRead(stdout: String, expected: AndroidNightModeReading) {
    #expect(ADBConditionCommands.parseNightModeRead(Self.result(0, stdout: stdout)) == .success(expected))
  }

  @Test("uimode 읽기 실패: 켜는 중·끊김 출력은 deviceNotBooted, 그 밖 unknown (던지지 않는다)")
  func nightModeReadFailure() {
    #expect(
      ADBConditionCommands
        .parseNightModeRead(Self.result(1, stderr: "adb: device offline\n")) == .failure(.deviceNotBooted)
    )
    #expect(
      ADBConditionCommands.parseNightModeRead(Self.result(20, stdout: "cmd: Can't find service: uimode\n"))
        == .failure(.deviceNotBooted)
    )
    #expect(ADBConditionCommands
      .parseNightModeRead(Self.result(255, stderr: "Unknown command: night\n")) == .success(.unknown))
  }

  @Test("uimode 쓰기: 새 값이 요청과 같으면 applied, 다르거나 Error 면 notApplied, 줄이 없으면 nil(다시 읽기)")
  func nightModeWrite() {
    func parse(
      _ result: CommandResult,
      _ requested: DeviceAppearance
    ) -> Result<AndroidConditionOutcome?, AndroidEmulatorError> {
      ADBConditionCommands.parseNightModeWrite(result, requested: requested)
    }
    #expect(parse(Self.result(0, stdout: "Night mode: yes\n"), .dark) == .success(.applied))
    #expect(parse(Self.result(0, stdout: "Night mode: no\n"), .light) == .success(.applied))
    #expect(parse(Self.result(0, stdout: "Night mode: no\n"), .dark) == .success(.notApplied))
    #expect(parse(Self.result(0, stdout: "Night mode: auto\n"), .dark) == .success(.notApplied))
    #expect(
      parse(
        Self.result(
          255,
          stderr: "Error: mode must be 'yes', 'no', or 'auto', or 'custom_schedule', or 'custom_bedtime'\n"
        ),
        .dark
      ) == .success(.notApplied)
    )
    #expect(parse(Self.result(0, stdout: "Error: something\n"), .dark) == .success(.notApplied))
    #expect(parse(Self.result(0, stdout: ""), .dark) == .success(nil))
    #expect(parse(Self.result(1, stderr: "adb: device offline\n"), .dark) == .failure(.deviceNotBooted))
  }

  @Test(
    "geo fix: OK → applied, KO: → notApplied, 둘 다 없으면 notApplied",
    arguments: [
      ("OK\r\n", AndroidConditionOutcome.applied),
      ("KO: invalid longitude value. Should be in [-180,+180] range\r\n", .notApplied),
      ("KO: argument ',9780 37,5665' is not a number\r\n", .notApplied),
      ("help text\r\nKO: missing sub-command\r\n", .notApplied),
      ("", .notApplied),
      ("OKAY\r\n", .notApplied),
    ]
  )
  func geoFix(stdout: String, expected: AndroidConditionOutcome) {
    #expect(ADBConditionCommands.parseGeoFix(Self.result(0, stdout: stdout)) == .success(expected))
  }

  @Test("geo fix 실패: 켜는 중·끊김 출력은 deviceNotBooted, 그 밖 adbUnavailable")
  func geoFixFailure() {
    #expect(
      ADBConditionCommands.parseGeoFix(Self.result(1, stderr: "adb: device 'emulator-5554' not found\n"))
        == .failure(.deviceNotBooted)
    )
    #expect(ADBConditionCommands
      .parseGeoFix(Self.result(1, stderr: "error: could not connect\n")) == .failure(.adbUnavailable))
  }

  @Test("위치 서비스: true/false 만, 그 밖·실패는 nil")
  func locationEnabled() {
    #expect(ADBConditionCommands.parseLocationEnabled(Self.result(0, stdout: "true\n")) == true)
    #expect(ADBConditionCommands.parseLocationEnabled(Self.result(0, stdout: "false\r\n")) == false)
    #expect(ADBConditionCommands.parseLocationEnabled(Self.result(0, stdout: "maybe\n")) == nil)
    #expect(ADBConditionCommands.parseLocationEnabled(Self.result(0, stdout: "")) == nil)
    #expect(ADBConditionCommands.parseLocationEnabled(Self.result(1, stdout: "true\n")) == nil)
  }
}
