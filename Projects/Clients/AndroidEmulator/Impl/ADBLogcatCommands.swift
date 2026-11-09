import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation

/// 로그 받기와 함께 하는 앱 실행(`launchWithLogcat`)의 adb 인자·기기 셸 스크립트와 출력 해석.
/// 스크립트에 넣는 값은 검사한 값뿐이다: 패키지는 `AndroidPackageName`(셸 특수 문자 없음), pid·uid 는 `Int` 로 읽은 값,
/// 시각은 숫자로 다시 만든 `<초>.<밀리 3자리>` 문자열. 그래서 인용하지 않는다 (`ADBAppCommands` 머리 설명과 같은 규칙).
enum ADBLogcatCommands {
  /// pid 기다림 루프 반복 수 (기기 안 0.1초 간격, 실측 번당 약 0.125초 → 약 7.5초).
  static let pidWaitAttempts = 60

  // MARK: - 인자

  /// 떠 있지 않거나 없는 패키지도 종료 0 (실측). 돌아온 직후 앞 프로세스는 없다 (실측).
  static func forceStopArguments(serial: String, package: AndroidPackageName) -> [String] {
    ["-s", serial, "shell", "am", "force-stop", package.rawValue]
  }

  /// 기기 epoch 시각 `1794201687.579556212` (CR 없음, 실측). Mac 시계와 다르므로 기기 값만 쓴다.
  static func deviceTimeArguments(serial: String) -> [String] {
    ["-s", serial, "shell", "date", "+%s.%N"]
  }

  /// 기기 안에서 `pidof` 를 0.1초 간격으로 다시 본다: 찾으면 pid 줄과 종료 0, 못 찾으면 종료 1.
  /// 처음 얻은 pid 로 바로 멈춘다 (새 프로세스가 보인 뒤 잠깐 빈 값으로 깜빡인다, 실측).
  static func pidWaitArguments(serial: String, package: AndroidPackageName) -> [String] {
    [
      "-s", serial, "shell",
      "for i in $(seq 1 \(self.pidWaitAttempts)); do p=$(pidof \(package.rawValue)) && { echo $p; exit 0; }; "
        + "sleep 0.1; done; exit 1",
    ]
  }

  /// `package:<패키지> uid:<uid>` (부분 일치로 거르므로 정확한 줄은 `parseUID` 가 고른다).
  static func uidArguments(serial: String, package: AndroidPackageName) -> [String] {
    ["-s", serial, "shell", "pm", "list", "packages", "-U", package.rawValue]
  }

  /// pid 전에 끝난 실행: 실행 직전 시각 뒤의 그 앱 uid 줄을 한 번 읽는다.
  static func uidLogArguments(serial: String, uid: Int, since time: String) -> [String] {
    ["-s", serial, "shell", "logcat", "-d", "--uid=\(uid)", "-v", "threadtime", "-T", time]
  }

  /// 받기: 기기 안 하위 셸이 앱 pid 를 0.2초 간격으로 보다가, 사라지면 1초 뒤(이미 끝난 pid 로 시작해도 앞 줄을 다 받게, 실측)
  /// 자기 logcat(`exec` 로 이 셸 pid `$$` 가 된다)을 끝낸다 → adb 143. 받기 adb 가 먼저 끝났으면(`[ -d /proc/$$ ]`) 보내지 않는다.
  /// logcat 을 `exec` 로 앞에 두어 호스트 SIGINT 때 기기에 고아가 남지 않는다 (logcat 을 `&` 뒤로 두면 남는다, 실측).
  static func streamArguments(serial: String, pid: Int, since time: String) -> [String] {
    [
      "-s", serial, "shell",
      "( while [ -d /proc/\(pid) ] && [ -d /proc/$$ ]; do sleep 0.2; done; sleep 1; [ -d /proc/$$ ] && kill $$ ) "
        + "& exec logcat --pid=\(pid) -v threadtime -T \(time)",
    ]
  }

  // MARK: - 출력 해석

  /// 켜는 중·끊김 문구면 `.deviceNotBooted`, 아니고 종료 0 이면 성공, 그 밖 `.appCommandFailed`.
  static func parseForceStop(_ result: CommandResult) -> Result<Void, AndroidEmulatorError> {
    if ADBAppCommands.notBooted(ADBAppCommands.lines(ADBAppCommands.text(result))) {
      return .failure(.deviceNotBooted)
    }
    return result.exitCode == 0 ? .success(()) : .failure(.appCommandFailed)
  }

  /// `1794201687.579556212` → `1794201687.579`. 소수가 3자리 미만이거나 숫자가 아니면(`%N` 을 모르는 셸) `.000`.
  /// **늘 `초.밀리` 형식이다**: `logcat -T <정수>` 는 시각이 아니라 줄 수로 읽힌다 (실측).
  /// 종료 코드 ≠ 0·초가 숫자 아님은 켜는 중·끊김 문구면 `.deviceNotBooted`, 아니면 `.appCommandFailed`.
  static func parseDeviceTime(_ result: CommandResult) -> Result<String, AndroidEmulatorError> {
    let text = String(bytes: result.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    guard
      result.exitCode == 0,
      let secondsText = parts.first,
      !secondsText.isEmpty,
      secondsText.allSatisfy(\.isASCIIDigit),
      let seconds = Int(secondsText)
    else {
      let notBooted = ADBAppCommands.notBooted(ADBAppCommands.lines(ADBAppCommands.text(result)))
      return .failure(notBooted ? .deviceNotBooted : .appCommandFailed)
    }
    var milliseconds = "000"
    if parts.count == 2 {
      let fraction = parts[1].prefix(3)
      if fraction.count == 3, fraction.allSatisfy(\.isASCIIDigit) {
        milliseconds = String(fraction)
      }
    }
    return .success("\(seconds).\(milliseconds)")
  }

  /// 판정 순서: ① 출력에 켜는 중·끊김 문구 → `.deviceNotBooted` (종료 1 이어도 먼저) ② 종료 0 → 첫 공백 앞 숫자(양수가 아니거나
  /// 숫자가 아니면 nil) ③ 종료 1 이고 출력이 비었음(stdout·stderr 모두 공백만. 기기 안 루프의 `exit 1`) → nil(못 찾음)
  /// ④ 그 밖(종료 1 인데 출력이 있음 — `error: device offline` 처럼 끊김 문구에 들지 않는 adb 오류 포함) → `.appCommandFailed`.
  static func parsePID(_ result: CommandResult) -> Result<Int?, AndroidEmulatorError> {
    if ADBAppCommands.notBooted(ADBAppCommands.lines(ADBAppCommands.text(result))) {
      return .failure(.deviceNotBooted)
    }
    let stdout = String(bytes: result.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let stderr = String(bytes: result.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    switch result.exitCode {
    case 0:
      let first = stdout.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
      guard first.allSatisfy(\.isASCIIDigit), let pid = Int(first), pid > 0 else {
        return .success(nil)
      }
      return .success(pid)
    case 1 where stdout.isEmpty && stderr.isEmpty:
      return .success(nil)
    default:
      return .failure(.appCommandFailed)
    }
  }

  /// 종료 0 인 출력에서 `package:<패키지>` 가 정확히 맞는 줄의 `uid:` 뒤 첫 숫자들 (`uid:10231,1010231` → 10231).
  /// 없거나 종료 코드 ≠ 0 이면 nil.
  static func parseUID(_ result: CommandResult, package: AndroidPackageName) -> Int? {
    guard result.exitCode == 0 else {
      return nil
    }
    for line in ADBAppCommands.lines(result.stdout) {
      let fields = line.split(whereSeparator: \.isWhitespace)
      guard fields.first == Substring("package:" + package.rawValue) else { continue }
      for field in fields.dropFirst() where field.hasPrefix("uid:") {
        let digits = field.dropFirst("uid:".count).prefix(while: \.isASCIIDigit)
        if let uid = Int(digits) {
          return uid
        }
      }
    }
    return nil
  }

  /// logcat 버퍼 머리 줄 (`--------- beginning of main`·`--------- switch to main` 등). threadtime 줄은 날짜로 시작한다.
  static func isHeaderLine(_ line: String) -> Bool {
    line.hasPrefix("--------- beginning of ") || line.hasPrefix("--------- switch to ")
  }

  /// 받기 adb 의 끝: 143(기기 안 감시가 보낸 `kill $$`, 앱이 끝남) → `.appExited`, 그 밖(기기 꺼짐 255·adb 실패) → `.connectionLost`.
  static func end(exitCode: Int32) -> AndroidLogcatEnd {
    exitCode == 143 ? .appExited : .connectionLost
  }
}

private extension Character {
  var isASCIIDigit: Bool {
    self.isASCII && self.isNumber
  }
}
