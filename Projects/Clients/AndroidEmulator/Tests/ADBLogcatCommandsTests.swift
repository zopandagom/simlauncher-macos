import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation
import Testing
@testable import AndroidEmulatorImpl

/// 로그 받기와 함께 하는 실행의 adb 인자·기기 셸 스크립트(정확히 비교)와 출력 해석. 출력은 설계 실측(API 37) 원문이다.
struct ADBLogcatCommandsTests {
  static let serial = "emulator-5554"
  static let package = AndroidPackageName("com.example.sample")!

  static func result(_ code: Int32, stdout: String = "", stderr: String = "") -> CommandResult {
    CommandResult(exitCode: code, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8))
  }

  static func failure(_ result: Result<some Any, AndroidEmulatorError>) -> AndroidEmulatorError? {
    if case let .failure(error) = result {
      return error
    }
    return nil
  }

  // MARK: - 인자

  @Test("인자: force-stop·date·pid 기다림·uid·한 번 읽기·받기 스크립트 (값은 검사한 값만, 인용 없음)")
  func arguments() {
    #expect(ADBLogcatCommands.forceStopArguments(serial: Self.serial, package: Self.package) == [
      "-s", "emulator-5554", "shell", "am", "force-stop", "com.example.sample",
    ])
    #expect(ADBLogcatCommands.deviceTimeArguments(serial: Self.serial) == [
      "-s", "emulator-5554", "shell", "date", "+%s.%N",
    ])
    #expect(ADBLogcatCommands.pidWaitArguments(serial: Self.serial, package: Self.package) == [
      "-s", "emulator-5554", "shell",
      "for i in $(seq 1 60); do p=$(pidof com.example.sample) && { echo $p; exit 0; }; sleep 0.1; done; exit 1",
    ])
    #expect(ADBLogcatCommands.uidArguments(serial: Self.serial, package: Self.package) == [
      "-s", "emulator-5554", "shell", "pm", "list", "packages", "-U", "com.example.sample",
    ])
    #expect(ADBLogcatCommands.uidLogArguments(serial: Self.serial, uid: 10231, since: "1794201687.579") == [
      "-s", "emulator-5554", "shell", "logcat", "-d", "--uid=10231", "-v", "threadtime", "-T", "1794201687.579",
    ])
    #expect(ADBLogcatCommands.streamArguments(serial: Self.serial, pid: 6502, since: "1794201687.579") == [
      "-s", "emulator-5554", "shell",
      "( while [ -d /proc/6502 ] && [ -d /proc/$$ ]; do sleep 0.2; done; sleep 1; [ -d /proc/$$ ] && kill $$ ) "
        + "& exec logcat --pid=6502 -v threadtime -T 1794201687.579",
    ])
    #expect(AndroidEmulatorClientImpl.Timing.standard.pidWaitTimeout == .seconds(30))
  }

  // MARK: - force-stop

  @Test("force-stop: 종료 0 이면 성공, 끊김 문구는 deviceNotBooted, 그 밖 appCommandFailed")
  func forceStop() {
    #expect(Self.failure(ADBLogcatCommands.parseForceStop(Self.result(0))) == nil)
    #expect(
      Self
        .failure(ADBLogcatCommands.parseForceStop(Self.result(1, stderr: "adb: device offline\n"))) == .deviceNotBooted
    )
    #expect(Self.failure(ADBLogcatCommands.parseForceStop(Self.result(255))) == .appCommandFailed)
  }

  // MARK: - 기기 시각

  @Test("기기 시각: 밀리 3자리로 자르고, 소수가 3자리 미만·숫자 아님이면 .000")
  func deviceTime() throws {
    let cases: [(String, String)] = [
      ("1794201687.579556212\n", "1794201687.579"),
      ("1794201687\n", "1794201687.000"),
      ("1794201687.%N\n", "1794201687.000"),
      ("1794201687.5\n", "1794201687.000"),
      ("1794201687.579556212\r\n", "1794201687.579"),
    ]
    for (stdout, expected) in cases {
      #expect(try ADBLogcatCommands.parseDeviceTime(Self.result(0, stdout: stdout)).get() == expected, "\(stdout)")
    }
  }

  @Test("기기 시각: 빈 값·숫자 아님·종료 코드 ≠ 0 은 실패 (끊김 문구면 deviceNotBooted, 아니면 appCommandFailed)")
  func deviceTimeFailures() {
    #expect(Self.failure(ADBLogcatCommands.parseDeviceTime(Self.result(0, stdout: ""))) == .appCommandFailed)
    #expect(Self.failure(ADBLogcatCommands.parseDeviceTime(Self.result(0, stdout: "abc\n"))) == .appCommandFailed)
    #expect(
      Self.failure(ADBLogcatCommands.parseDeviceTime(Self.result(1, stdout: "1794201687.579556212\n")))
        == .appCommandFailed
    )
    #expect(
      Self.failure(ADBLogcatCommands.parseDeviceTime(Self.result(1, stderr: "adb: device 'emulator-5554' not found\n")))
        == .deviceNotBooted
    )
  }

  // MARK: - pid

  @Test("pid: 종료 0 이면 첫 공백 앞 숫자, 숫자 아님·0 이하는 nil, 종료 1 이고 stdout 이 비면 nil")
  func pid() throws {
    #expect(try ADBLogcatCommands.parsePID(Self.result(0, stdout: "6502\n")).get() == 6502)
    #expect(try ADBLogcatCommands.parsePID(Self.result(0, stdout: "6502 6510\n")).get() == 6502)
    #expect(try ADBLogcatCommands.parsePID(Self.result(0, stdout: "abc\n")).get() == nil)
    #expect(try ADBLogcatCommands.parsePID(Self.result(0, stdout: "0\n")).get() == nil)
    #expect(try ADBLogcatCommands.parsePID(Self.result(0, stdout: "-3\n")).get() == nil)
    #expect(try ADBLogcatCommands.parsePID(Self.result(1)).get() == nil)
    #expect(try ADBLogcatCommands.parsePID(Self.result(1, stdout: " \n")).get() == nil)
  }

  @Test("pid: 끊김 문구는 종료 1 이어도 먼저 deviceNotBooted, 종료 1 인데 stdout 이 있거나 다른 코드·다른 adb 오류는 appCommandFailed")
  func pidFailures() {
    #expect(
      Self.failure(ADBLogcatCommands.parsePID(Self.result(1, stderr: "adb: device 'emulator-5554' not found\n")))
        == .deviceNotBooted
    )
    #expect(Self.failure(ADBLogcatCommands.parsePID(Self.result(1, stdout: "Error: closed\n"))) == .deviceNotBooted)
    #expect(Self
      .failure(ADBLogcatCommands.parsePID(Self.result(1, stdout: "sh: seq: not found\n"))) == .appCommandFailed)
    #expect(Self.failure(ADBLogcatCommands.parsePID(Self.result(255))) == .appCommandFailed)
    #expect(
      Self.failure(ADBLogcatCommands.parsePID(Self.result(1, stderr: "error: device offline\n"))) == .appCommandFailed
    )
  }

  // MARK: - uid

  @Test("uid: 접두가 같은 다른 패키지 줄을 건너뛰고 정확한 줄의 첫 숫자들, 없거나 실패면 nil")
  func uid() {
    let listed = Self.result(
      0,
      stdout: "package:com.example.sample.rro uid:10079\npackage:com.example.sample uid:10231\n"
    )
    #expect(ADBLogcatCommands.parseUID(listed, package: Self.package) == 10231)
    let multiUser = Self.result(0, stdout: "package:com.example.sample uid:10231,1010231\n")
    #expect(ADBLogcatCommands.parseUID(multiUser, package: Self.package) == 10231)
    let other = Self.result(0, stdout: "package:com.example.sample.rro uid:10079\n")
    #expect(ADBLogcatCommands.parseUID(other, package: Self.package) == nil)
    #expect(ADBLogcatCommands.parseUID(Self.result(0), package: Self.package) == nil)
    #expect(
      ADBLogcatCommands.parseUID(
        Self.result(1, stdout: "package:com.example.sample uid:10231\n"),
        package: Self.package
      )
        == nil
    )
  }

  // MARK: - 줄·끝

  @Test("머리 줄: beginning of·switch to 는 빠지고 그 밖(빈 줄·threadtime 줄·탭 줄)은 남는다")
  func headerLines() {
    #expect(ADBLogcatCommands.isHeaderLine("--------- beginning of main"))
    #expect(ADBLogcatCommands.isHeaderLine("--------- beginning of crash"))
    #expect(ADBLogcatCommands.isHeaderLine("--------- switch to main"))
    #expect(!ADBLogcatCommands.isHeaderLine(""))
    #expect(!ADBLogcatCommands.isHeaderLine("11-09 10:00:00.000  6502  6502 I Zygote: Process 6502 created"))
    #expect(!ADBLogcatCommands.isHeaderLine("\tat com.example.sample.Main.onCreate(Main.java:10)"))
    #expect(!ADBLogcatCommands.isHeaderLine("---------"))
  }

  @Test("받기 끝: 143 은 appExited, 그 밖은 connectionLost")
  func end() {
    #expect(ADBLogcatCommands.end(exitCode: 143) == .appExited)
    for code: Int32 in [255, 1, 130, 0] {
      #expect(ADBLogcatCommands.end(exitCode: code) == .connectionLost, "\(code)")
    }
  }
}
