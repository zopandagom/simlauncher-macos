import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation

/// 켜진 기기의 앱 작업(값 읽기·설치·실행·링크 열기·앱 목록) adb 인자와 출력 해석.
/// `shell` 뒤 사용자 값·기기에서 읽은 값(링크·component)은 `ADBShell.quote` 를 거친다. 패키지 이름은 `AndroidPackageName` 이라
/// 셸 특수 문자가 없어 인용하지 않는다. install 의 apk 경로는 호스트 argv 라 인용하지 않는다 (`/` 로 시작해 옵션으로 읽히지 않는다).
enum ADBAppCommands {
  /// `resolve-activity` 결과. `ambiguous` 는 launcher 가 둘 이상이라 기기가 고르기 화면
  /// (`android/com.android.internal.app.ResolverActivity`, 실측)을 돌려준 경우로, 그 component 는 `am start` 에 넘기지 않는다.
  enum ResolvedLauncher: Equatable {
    case component(String)
    case none
    case ambiguous
  }

  // MARK: - 인자

  /// `getprop` 두 번: API 수준, ABI 목록.
  static func traitsArguments(serial: String) -> (apiLevel: [String], abis: [String]) {
    (
      ["-s", serial, "shell", "getprop", "ro.build.version.sdk"],
      ["-s", serial, "shell", "getprop", "ro.product.cpu.abilist"]
    )
  }

  /// `-r` 덮어쓰기, `-t` testOnly 허용, `-d` 다운그레이드 허용(데이터 유지), `--no-incremental` 증분 설치 끔
  /// (증분 설치는 설치 뒤에도 호스트 파일을 읽을 수 있다).
  static func installArguments(serial: String, apk: URL) -> [String] {
    ["-s", serial, "install", "-r", "-t", "-d", "--no-incremental", FileFacts.path(apk)]
  }

  static func resolveArguments(serial: String, package: AndroidPackageName) -> [String] {
    [
      "-s", serial, "shell", "cmd", "package", "resolve-activity", "--brief",
      "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", package.rawValue,
    ]
  }

  /// 기기가 하나로 고르지 못했을 때만 쓴다. 순서는 manifest 선언 순서다 (실측).
  static func launchersArguments(serial: String, package: AndroidPackageName) -> [String] {
    [
      "-s", serial, "shell", "cmd", "package", "query-activities", "--brief",
      "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", package.rawValue,
    ]
  }

  static func packagePathArguments(serial: String, package: AndroidPackageName) -> [String] {
    ["-s", serial, "shell", "pm", "path", package.rawValue]
  }

  /// `-W` 는 쓰지 않는다 (기다려도 시작 직후 죽는 앱을 가르지 못하고 1~3초 늦다, 실측). component 의 클래스 이름에 `$` 가 올 수 있다.
  static func startArguments(serial: String, component: String) -> [String] {
    ["-s", serial, "shell", "am", "start", "-n", ADBShell.quote(component)]
  }

  static func openURLArguments(serial: String, link: DeepLink) -> [String] {
    [
      "-s", serial, "shell", "am", "start", "-a", "android.intent.action.VIEW",
      "-d", ADBShell.quote(link.url.absoluteString),
    ]
  }

  static func listPackagesArguments(serial: String) -> [String] {
    ["-s", serial, "shell", "pm", "list", "packages", "-3"]
  }

  // MARK: - 출력 해석

  /// `37\r\n` → 37. 종료 코드 ≠ 0·빈 값·숫자 아님은 `.deviceNotBooted`.
  static func parseAPILevel(_ result: CommandResult) -> Result<Int, AndroidEmulatorError> {
    guard
      result.exitCode == 0,
      let text = String(bytes: result.stdout, encoding: .utf8),
      let level = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
      return .failure(.deviceNotBooted)
    }
    return .success(level)
  }

  /// `arm64-v8a,armeabi-v7a\r\n` → 순서 그대로. 쉼표로 나눠 빈 것은 뺀다. 종료 코드 ≠ 0·빈 목록은 `.deviceNotBooted`.
  static func parseABIs(_ result: CommandResult) -> Result<[String], AndroidEmulatorError> {
    guard result.exitCode == 0, let text = String(bytes: result.stdout, encoding: .utf8) else {
      return .failure(.deviceNotBooted)
    }
    let abis = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    return abis.isEmpty ? .failure(.deviceNotBooted) : .success(abis)
  }

  /// 종료 코드 0 이고 stdout 에 `Success` 줄이면 성공. 아니면 stdout·stderr 의 마지막 `Failure [` 뒤 코드(`:`·`]`·공백 전까지)를
  /// 표로 바꾼다. 표에 없으면 `INSTALL_[A-Z0-9_]+` 와 정확히 맞을 때만 `.other(코드)`. 코드가 없으면 adb 문구 형태로만 본다:
  /// 켜는 중·끊김(`notBooted`) → `.deviceNotBooted`, `adb: filename doesn't end .apk` → `.notAPK`, 그 밖 `.other(nil)`.
  /// 출력에는 사용자 경로가 들어 있어 부분 문자열(`closed`·`not found`)만으로 판정하지 않는다.
  static func parseInstall(_ result: CommandResult) -> Result<Void, AndroidEmulatorError> {
    if result.exitCode == 0, self.lines(result.stdout).contains("Success") {
      return .success(())
    }
    let text = self.text(result)
    if let code = self.failureCode(text) {
      return .failure(.installFailed(self.installFailure(code: code)))
    }
    let lines = self.lines(text)
    if self.notBooted(lines) {
      return .failure(.deviceNotBooted)
    }
    if lines.contains(where: { $0.hasPrefix("adb: filename doesn't end .apk") }) {
      return .failure(.installFailed(.notAPK))
    }
    return .failure(.installFailed(.other(nil)))
  }

  /// 마지막 비지 않은 줄이 `<패키지>/` 로 시작하고 공백이 없으면 그 component (`pkg/.Main` 짧은 형식 그대로), `No activity found`
  /// 면 `.none`(설치 안 됨과 화면 없음이 같다), 공백 없는 다른 패키지의 `<a>/<b>` 면 `.ambiguous` (고르기 화면 이름은 Android 버전·
  /// 제조사마다 다를 수 있어 정확히 비교하지 않는다). 켜는 중·끊김은 `.deviceNotBooted`, 그 밖은 `.appCommandFailed`.
  static func parseResolve(
    _ result: CommandResult,
    package: AndroidPackageName
  ) -> Result<ResolvedLauncher, AndroidEmulatorError> {
    let lines = self.lines(self.text(result))
    if result.exitCode == 0, let last = self.lines(result.stdout).last {
      if self.isComponent(last, of: package) {
        return .success(.component(last))
      }
      if last == "No activity found" {
        return .success(.none)
      }
      if self.isComponent(last) {
        return .success(.ambiguous)
      }
    }
    return .failure(self.notBooted(lines) ? .deviceNotBooted : .appCommandFailed)
  }

  /// `query-activities --brief`: 종료 코드 0 이면 `<패키지>/` 로 시작하고 공백이 없는 줄을 순서대로. 없고 `No activities found` 줄이
  /// 있으면 빈 목록. 그 밖은 켜는 중·끊김이면 `.deviceNotBooted`, 아니면 `.appCommandFailed`.
  static func parseLaunchers(
    _ result: CommandResult,
    package: AndroidPackageName
  ) -> Result<[String], AndroidEmulatorError> {
    if result.exitCode == 0 {
      let stdout = self.lines(result.stdout)
      let components = stdout.filter { self.isComponent($0, of: package) }
      if !components.isEmpty {
        return .success(components)
      }
      if stdout.contains("No activities found") {
        return .success([])
      }
    }
    return .failure(self.notBooted(self.lines(self.text(result))) ? .deviceNotBooted : .appCommandFailed)
  }

  /// 종료 코드 0 → 설치됨, 1 → 없음. 켜는 중·끊김은 `.deviceNotBooted`, 그 밖 `.appCommandFailed`.
  static func parsePackagePath(_ result: CommandResult) -> Result<Bool, AndroidEmulatorError> {
    if self.notBooted(self.lines(self.text(result))) {
      return .failure(.deviceNotBooted)
    }
    switch result.exitCode {
    case 0: return .success(true)
    case 1: return .success(false)
    default: return .failure(.appCommandFailed)
    }
  }

  /// 종료 코드 0 이고 `Error` 로 시작하는 줄이 없으면 성공 (`Warning: Activity not started, intent has been delivered…` 포함).
  /// `unable to resolve Intent` → `.urlNotHandled`, 켜는 중·끊김 → `.deviceNotBooted`, 그 밖(`does not exist` 포함)
  /// `.appCommandFailed`.
  static func parseStart(_ result: CommandResult) -> Result<Void, AndroidEmulatorError> {
    let lines = self.lines(self.text(result))
    if result.exitCode == 0, !lines.contains(where: { $0.hasPrefix("Error") }) {
      return .success(())
    }
    if lines.contains(where: { $0.contains("unable to resolve Intent") }) {
      return .failure(.urlNotHandled)
    }
    return .failure(self.notBooted(lines) ? .deviceNotBooted : .appCommandFailed)
  }

  /// `package:<이름>` 줄 → 이름순·중복 없음. 형식에 맞지 않는 줄은 건너뛴다. 종료 코드 ≠ 0 이면 켜는 중·끊김은
  /// `.deviceNotBooted`, 그 밖 `.appCommandFailed`.
  static func parsePackages(_ result: CommandResult) -> Result<[AndroidPackageName], AndroidEmulatorError> {
    guard result.exitCode == 0 else {
      return .failure(self.notBooted(self.lines(self.text(result))) ? .deviceNotBooted : .appCommandFailed)
    }
    let names = self.lines(result.stdout).compactMap { line -> AndroidPackageName? in
      guard line.hasPrefix("package:") else {
        return nil
      }
      return AndroidPackageName(String(line.dropFirst("package:".count)))
    }
    return .success(Set(names).sorted())
  }

  // MARK: - 도우미

  static let installFailures: [String: AndroidInstallFailure] = [
    "INSTALL_FAILED_OLDER_SDK": .olderSDK,
    "INSTALL_FAILED_NO_MATCHING_ABIS": .noMatchingABIs,
    "INSTALL_FAILED_UPDATE_INCOMPATIBLE": .updateIncompatible,
    "INSTALL_FAILED_SHARED_USER_INCOMPATIBLE": .updateIncompatible,
    "INSTALL_FAILED_VERSION_DOWNGRADE": .versionDowngrade,
    "INSTALL_PARSE_FAILED_NO_CERTIFICATES": .noCertificates,
    "INSTALL_PARSE_FAILED_NOT_APK": .notAPK,
    "INSTALL_FAILED_INVALID_APK": .notAPK,
    "INSTALL_FAILED_DEPRECATED_SDK_VERSION": .deprecatedSDK,
    "INSTALL_FAILED_INSUFFICIENT_STORAGE": .insufficientStorage,
    "INSTALL_FAILED_DUPLICATE_PERMISSION": .conflict,
    "INSTALL_FAILED_CONFLICTING_PROVIDER": .conflict,
    "INSTALL_FAILED_MISSING_SHARED_LIBRARY": .missingSharedLibrary,
    "INSTALL_FAILED_TEST_ONLY": .testOnly,
    "INSTALL_FAILED_MISSING_SPLIT": .missingSplit,
  ]

  static func installFailure(code: String) -> AndroidInstallFailure {
    if let known = self.installFailures[code] {
      return known
    }
    return code.wholeMatch(of: /INSTALL_[A-Z0-9_]+/) != nil ? .other(code) : .other(nil)
  }

  /// 마지막 `Failure [` 뒤 `:`·`]`·공백 전까지 (경로에 같은 글자가 있어도 adb 문구는 경로 뒤에 온다). 비면 nil.
  static func failureCode(_ text: String) -> String? {
    guard let marker = text.range(of: "Failure [", options: .backwards) else {
      return nil
    }
    let code = text[marker.upperBound...].prefix { $0 != ":" && $0 != "]" && !$0.isWhitespace }
    return code.isEmpty ? nil : String(code)
  }

  /// 켜는 중·꺼지는 중 adb·기기 문구 (실측): `adb: device offline`, `adb: device '<serial>' not found` 줄, 또는
  /// `Error: closed`·`Error: device offline`·`Error: device is still booting.`·`cmd: Can't find service: `·
  /// `Too early to start activity` 를 담은 줄.
  static func notBooted(_ lines: [String]) -> Bool {
    let fragments = [
      "Error: closed", "Error: device offline", "Error: device is still booting.",
      "cmd: Can't find service: ", "Too early to start activity",
    ]
    return lines.contains { line in
      line == "adb: device offline"
        || (line.hasPrefix("adb: device '") && line.hasSuffix("' not found"))
        || fragments.contains { line.contains($0) }
    }
  }

  /// 공백 없이 `<패키지>/` 로 시작하는 줄.
  private static func isComponent(_ line: String, of package: AndroidPackageName) -> Bool {
    line.hasPrefix(package.rawValue + "/") && !line.contains(where: \.isWhitespace)
  }

  /// 공백 없는 `<a>/<b>` (a·b 비지 않음, `/` 하나).
  private static func isComponent(_ line: String) -> Bool {
    let parts = line.split(separator: "/", omittingEmptySubsequences: false)
    return parts.count == 2 && parts.allSatisfy { !$0.isEmpty } && !line.contains(where: \.isWhitespace)
  }

  /// stdout 다음 stderr.
  private static func text(_ result: CommandResult) -> String {
    let stdout = String(bytes: result.stdout, encoding: .utf8) ?? ""
    let stderr = String(bytes: result.stderr, encoding: .utf8) ?? ""
    return stdout + "\n" + stderr
  }

  private static func lines(_ data: Data) -> [String] {
    self.lines(String(bytes: data, encoding: .utf8) ?? "")
  }

  /// 앞뒤 공백을 뺀 비지 않은 줄 (CRLF 포함).
  private static func lines(_ text: String) -> [String] {
    text.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }
}
