import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation

/// 런타임 권한(테스트 조건) adb 인자와 출력 해석 (순수). 권한 이름은 기기 출력에서 읽은 값이라 `ADBShell.quote` 를 거치고,
/// 패키지 이름은 `AndroidPackageName` 이라 인용하지 않는다 (`ADBAppCommands` 규칙). 켜는 중·끊김 판정은 `ADBAppCommands.notBooted`.
/// 출력 형식은 TC-B 실측(API 37) 기준이다.
enum ADBPermissionCommands {
  /// grant·revoke·clear-permission-flags 해석 결과.
  enum ChangeStatus: Equatable {
    /// 명령이 돌았다 (값이 바뀌었는지는 다시 읽어 판정한다).
    case ran
    case appNotInstalled
  }

  // MARK: - 인자

  /// 그 패키지 하나의 상태 (지도 261 KB, 0.04초, 실측).
  static func dumpsysPackageArguments(serial: String, package: AndroidPackageName) -> [String] {
    ["-s", serial, "shell", "dumpsys", "package", package.rawValue]
  }

  /// 성공·이미 같은 값은 출력 없이 exit 0 (실측).
  static func grantArguments(
    serial: String,
    package: AndroidPackageName,
    permission: AndroidRuntimePermission
  ) -> [String] {
    ["-s", serial, "shell", "pm", "grant", package.rawValue, ADBShell.quote(permission.rawValue)]
  }

  static func revokeArguments(
    serial: String,
    package: AndroidPackageName,
    permission: AndroidRuntimePermission
  ) -> [String] {
    ["-s", serial, "shell", "pm", "revoke", package.rawValue, ADBShell.quote(permission.rawValue)]
  }

  /// "다시 묻지 않음"(USER_FIXED)과 사용자가 고른 표시(USER_SET)를 지운다: revoke 는 있는 USER_FIXED 를 지우지 않아 앱이 다시 물을 수
  /// 없는 상태가 남는다 (실측). 미설치·미선언 패키지/권한에도 exit 0 (실측).
  static func clearFlagsArguments(
    serial: String,
    package: AndroidPackageName,
    permission: AndroidRuntimePermission
  ) -> [String] {
    [
      "-s", serial, "shell", "pm", "clear-permission-flags", package.rawValue, ADBShell.quote(permission.rawValue),
      "user-set", "user-fixed",
    ]
  }

  // MARK: - 출력 해석

  /// `dumpsys package <패키지>` 해석:
  /// 1. 종료 코드 ≠ 0 → 켜는 중·끊김 출력이면 `.deviceNotBooted`, 아니면 `.appCommandFailed`.
  /// 2. stdout 에 앞뒤 공백을 뺀 줄이 정확히 `Unable to find package: <패키지>` (exit 0, 실측) → `.appNotInstalled`.
  /// 3. 최상위 절(열 0 에서 시작해 `:` 로 끝나는 줄)로 나눈다. `Packages:` 절에 앞 공백 뒤 `Package [<패키지>]` 로 시작하는 줄이 없으면
  ///    켜는 중 출력이면 `.deviceNotBooted`, 아니면 `.appCommandFailed` (잘린 출력). 켜는 중 출력은 1 의 문구와 `Can't find service: `
  ///    로 시작하는 줄이다 (서비스 이름은 보지 않는다. 실측: 부팅 중 dumpsys 가 stderr 에 `Can't find service: package` 를 쓰고 exit 0,
  ///    `cmd:` 접두어 없음).
  ///    부팅 중 잠깐 나오는 `Permission Denial: can't dump PackageManager …`(exit 0, 실측)는 `.appCommandFailed` 다.
  /// 4. `Packages:`·`Shared users:` 절(공유 uid 앱은 `Shared users:` 에 있다, 실측)에서 앞뒤 공백을 뺀 값이 `runtime permissions:` 인
  ///    머리 줄 중, 위로 가장 가까운 들여쓰기가 더 작은 줄이 `User 0:` 로 시작하는 것만 쓴다. 그런 머리 줄이 하나도 없으면
  ///    `.appCommandFailed`.
  /// 5. 블록은 머리 줄보다 깊게 들여쓴 줄이 이어지는 동안이다 (빈 줄·들여쓰기가 같거나 얕은 줄에서 끝). 줄 `<이름>: granted=<true|false>`
  ///    (`,` 뒤 flags 는 무시). 이름이 `AndroidRuntimePermission` 형식이 아니거나 값이 둘 중 하나가 아니면 그 줄만 건너뛴다.
  ///    같은 이름이 두 블록에 있으면 뒤의 값을 앞 자리에 둔다. 머리 줄만 있고 비었으면 `.runtime([])`.
  static func parseRuntimePermissions(
    _ result: CommandResult,
    package: AndroidPackageName
  ) -> Result<AndroidAppPermissions, AndroidEmulatorError> {
    guard result.exitCode == 0 else {
      return .failure(self.notBooted(result) ? .deviceNotBooted : .appCommandFailed)
    }
    let lines = self.rawLines(result.stdout)
    let missing = "Unable to find package: " + package.rawValue
    if lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == missing }) {
      return .success(.appNotInstalled)
    }
    let sections = self.sections(lines)
    let packageHead = "Package [" + package.rawValue + "]"
    guard
      let packages = sections["Packages:"],
      packages.contains(where: { $0.drop(while: \.isWhitespace).hasPrefix(packageHead) })
    else {
      return .failure(self.dumpsysBooting(result) ? .deviceNotBooted : .appCommandFailed)
    }
    var blocks: [[String]] = []
    for name in ["Packages:", "Shared users:"] {
      blocks += self.userZeroRuntimeBlocks(sections[name] ?? [])
    }
    guard !blocks.isEmpty else {
      return .failure(.appCommandFailed)
    }
    var grants: [AndroidPermissionGrant] = []
    for line in blocks.joined() {
      guard let grant = self.grant(line) else {
        continue
      }
      if let index = grants.firstIndex(where: { $0.permission == grant.permission }) {
        grants[index] = grant
      } else {
        grants.append(grant)
      }
    }
    return .success(.runtime(grants))
  }

  /// grant·revoke·clear-permission-flags 해석: 종료 코드 0 → `.ran`. 어느 줄이 `Failure [package not found]`·
  /// `Error: package not found` → `.appNotInstalled` (실측 출처는 grant·revoke 의 exit 1. clear-permission-flags 는 미설치에도
  /// exit 0 이라 `.ran`, 실측). 켜는 중·끊김 → `.deviceNotBooted`.
  /// 종료 코드 255 이고 `java.lang.SecurityException`(바꿀 수 없는 권한)·`java.lang.IllegalArgumentException`(없는 권한)으로
  /// 시작하는 줄 → `.ran` (다시 읽어 적용 안 됨으로 판정되게). 그 밖 → `.appCommandFailed`.
  static func parseChange(_ result: CommandResult) -> Result<ChangeStatus, AndroidEmulatorError> {
    if result.exitCode == 0 {
      return .success(.ran)
    }
    let lines = ADBAppCommands.lines(ADBAppCommands.text(result))
    if lines.contains(where: { $0 == "Failure [package not found]" || $0 == "Error: package not found" }) {
      return .success(.appNotInstalled)
    }
    if ADBAppCommands.notBooted(lines) {
      return .failure(.deviceNotBooted)
    }
    let exceptions = ["java.lang.SecurityException", "java.lang.IllegalArgumentException"]
    if result.exitCode == 255, lines.contains(where: { line in exceptions.contains { line.hasPrefix($0) } }) {
      return .success(.ran)
    }
    return .failure(.appCommandFailed)
  }

  // MARK: - 도우미

  /// 들여쓰기는 그대로 둔 줄 (빈 줄 포함). LF·CRLF 모두 줄 끝으로 본다 (Swift 에서 `\r\n` 은 한 Character 라
  /// `"\n"` 으로는 나뉘지 않으므로 `ADBAppCommands.lines` 처럼 `isNewline` 으로 나눈다).
  private static func rawLines(_ data: Data) -> [String] {
    (String(bytes: data, encoding: .utf8) ?? "")
      .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .map(String.init)
  }

  /// 최상위 절 이름(열 0 에서 시작해 `:` 로 끝나는 줄) → 그 아래 줄들. 같은 이름이 여러 번 나오면(`Permissions:`) 이어 붙인다.
  /// 첫 절 앞의 줄은 버린다.
  private static func sections(_ lines: [String]) -> [String: [String]] {
    var sections: [String: [String]] = [:]
    var current: String?
    for line in lines {
      if let first = line.first, !first.isWhitespace, line.hasSuffix(":") {
        current = line
        sections[line, default: []] += []
      } else if let current {
        sections[current, default: []].append(line)
      }
    }
    return sections
  }

  /// 절 안에서 user 0 의 `runtime permissions:` 블록 줄들. 블록이 비었어도 빈 배열 하나로 센다.
  private static func userZeroRuntimeBlocks(_ lines: [String]) -> [[String]] {
    var blocks: [[String]] = []
    for (index, line) in lines.enumerated() where line.trimmingCharacters(in: .whitespaces) == "runtime permissions:" {
      let indent = self.indent(line)
      let parent = lines[..<index].last { !$0.allSatisfy(\.isWhitespace) && self.indent($0) < indent }
      guard let parent, parent.drop(while: \.isWhitespace).hasPrefix("User 0:") else {
        continue
      }
      let body = lines[(index + 1)...].prefix { !$0.allSatisfy(\.isWhitespace) && self.indent($0) > indent }
      blocks.append(Array(body))
    }
    return blocks
  }

  private static func indent(_ line: String) -> Int {
    line.prefix(while: \.isWhitespace).count
  }

  /// `<이름>: granted=<true|false>[, flags=[ … ]]`. 형식이 다르면 nil.
  private static func grant(_ line: String) -> AndroidPermissionGrant? {
    let text = line.trimmingCharacters(in: .whitespaces)
    guard let marker = text.range(of: ": granted=") else {
      return nil
    }
    let value = text[marker.upperBound...].prefix { $0 != "," }
    let isGranted: Bool
    switch value {
    case "true": isGranted = true
    case "false": isGranted = false
    default: return nil
    }
    guard let permission = AndroidRuntimePermission(String(text[..<marker.lowerBound])) else {
      return nil
    }
    return AndroidPermissionGrant(permission: permission, isGranted: isGranted)
  }

  private static func notBooted(_ result: CommandResult) -> Bool {
    ADBAppCommands.notBooted(ADBAppCommands.lines(ADBAppCommands.text(result)))
  }

  /// `Packages:` 절이 없는 exit 0 dumpsys 출력이 켜는 중인지: 공통 켜는 중 문구, 또는 `Can't find service: ` 로 시작하는 줄
  /// (서비스가 아직 없을 때 dumpsys 가 stderr 에 쓴다, exit 0, 실측).
  private static func dumpsysBooting(_ result: CommandResult) -> Bool {
    let lines = ADBAppCommands.lines(ADBAppCommands.text(result))
    return ADBAppCommands.notBooted(lines) || lines.contains { $0.hasPrefix("Can't find service: ") }
  }
}
