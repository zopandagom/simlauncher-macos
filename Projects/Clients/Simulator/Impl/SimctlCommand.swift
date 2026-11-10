import Foundation

/// 실행할 명령과 인자·환경 (순수).
enum SimctlCommand {
  static let xcrun = URL(filePath: "/usr/bin/xcrun")
  static let xcodeSelect = URL(filePath: "/usr/bin/xcode-select")
  static let open = URL(filePath: "/usr/bin/open")

  static func list() -> [String] {
    ["simctl", "list", "-j"]
  }

  /// 런타임 디스크 이미지 목록 (상태 포함). `list -j` 의 runtimes 와 달리 설치·삭제 중인 이미지도 보인다.
  static func runtimeList() -> [String] {
    ["simctl", "runtime", "list", "-j"]
  }

  /// `udid` 는 `validatedUDID(_:)` 를 거친 값만 넘긴다 (simctl 은 기기 이름·옵션도 받는다).
  static func boot(udid: String) -> [String] {
    ["simctl", "boot", udid]
  }

  /// `udid` 는 `validatedUDID(_:)` 를 거친 값만 넘긴다.
  static func shutdown(udid: String) -> [String] {
    ["simctl", "shutdown", udid]
  }

  /// 이름 앞에 `--` 를 둬 `-` 로 시작하는 이름이 옵션으로 해석되지 않게 한다 (create 는 `-h` 를 옵션으로 본다).
  /// ID 는 `DeviceCreationOptions.contains` 를 통과한 값만 넘긴다 (simctl 은 기기 종류·런타임 이름도 받는다).
  static func create(name: String, deviceTypeID: String, runtimeID: String) -> [String] {
    ["simctl", "create", "--", name, deviceTypeID, runtimeID]
  }

  /// `udid` 는 `validatedUDID(_:)` 를 거친 값만 넘긴다 (delete 는 "all"·"unavailable" 도 받는다).
  /// delete·erase 는 `--` 를 기기 이름으로 보므로 붙이지 않는다.
  static func delete(udid: String) -> [String] {
    ["simctl", "delete", udid]
  }

  /// `udid` 는 `validatedUDID(_:)` 를 거친 값만 넘긴다. `--` 는 붙이지 않는다 (`delete(udid:)` 참고).
  static func erase(udid: String) -> [String] {
    ["simctl", "erase", udid]
  }

  /// 기기에 설치된 앱 목록 (OpenStep plist). `udid` 는 `validatedUDID(_:)` 를 거친 값만 넘긴다.
  /// `--` 는 붙이지 않는다 (다른 기기 명령과 같이 기기 인자 하나만 받는다. 붙여 보지는 않았다).
  static func listApps(udid: String) -> [String] {
    ["simctl", "listapps", udid]
  }

  /// 기기 안 launchd 의 작업 목록 (탭으로 나눈 `PID Status Label` 줄). 떠 있는 앱은 `UIKitApplication:<번들 ID>[…]` 레이블이다.
  /// `udid` 는 `validatedUDID(_:)` 를 거친 값만 넘긴다. 뒤 인자는 고정 값이다.
  static func spawnLaunchctlList(udid: String) -> [String] {
    ["simctl", "spawn", udid, "launchctl", "list"]
  }

  /// 앱 지우기. 인자 규칙은 `launch(udid:bundleID:)` 와 같다 (`udid` 는 `validatedUDID(_:)`, `bundleID` 는 `AppBundleID` 형식 검사를 거친 값,
  /// `--` 없음).
  static func uninstall(udid: String, bundleID: String) -> [String] {
    ["simctl", "uninstall", udid, bundleID]
  }

  /// `udid` 는 `validatedUDID(_:)` 를 거친 값, `appPath` 는 파일 URL 의 표준화한 절대 경로만 넘긴다 (`/` 로 시작해 옵션으로
  /// 읽히지 않는다). install 은 `--` 를 경로로 보므로 붙이지 않는다.
  static func install(udid: String, appPath: String) -> [String] {
    ["simctl", "install", udid, appPath]
  }

  /// `udid` 는 `validatedUDID(_:)` 를 거친 값, `bundleID` 는 `AppBundleID` 형식 검사를 거친 값만 넘긴다.
  /// 기기 뒤 인자는 옵션으로 해석되지 않고, launch 는 `--` 를 번들 ID 로 보므로 붙이지 않는다.
  static func launch(udid: String, bundleID: String) -> [String] {
    ["simctl", "launch", udid, bundleID]
  }

  /// 콘솔을 붙인 실행. 인자 규칙은 `launch(udid:bundleID:)` 와 같다 (`--` 없음).
  /// `--console-pty` 는 앱의 stdout·stderr 를 pty 로 받아 simctl stdout 하나로 넘기고(앱 줄 끝 `\r\n`), `--terminate-running-process` 는
  /// 이미 실행 중인 앱을 끝내고 다시 띄운다 (끝난 앞 실행의 simctl 도 곧 끝난다, 측정).
  static func launchWithConsole(udid: String, bundleID: String) -> [String] {
    ["simctl", "launch", "--console-pty", "--terminate-running-process", udid, bundleID]
  }

  /// `udid` 는 `validatedUDID(_:)` 를 거친 값, `url` 은 `DeepLink.url.absoluteString`(스킴으로 시작)만 넘긴다.
  /// openurl 은 기기 뒤 인자를 옵션으로 읽지 않고 `--` 도 URL 로 받으므로(-50) 붙이지 않는다.
  static func openURL(udid: String, url: String) -> [String] {
    ["simctl", "openurl", udid, url]
  }

  /// `udid` 는 `validatedUDID(_:)` 를 거친 값, `path` 는 파일 URL 의 표준화한 절대 경로만 넘긴다 (`/` 로 시작해 옵션으로
  /// 읽히지 않는다). `--mask=ignored` 는 기본값과 같지만 simctl 기본이 바뀌어도 사각 전체 화면이 되게 명시한다.
  static func screenshot(udid: String, path: String) -> [String] {
    ["simctl", "io", udid, "screenshot", "--type=png", "--mask=ignored", path]
  }

  /// `udid` 는 `validatedUDID(_:)` 를 거친 값, `path` 는 파일 URL 의 표준화한 절대 경로만 넘긴다 (`/` 로 시작해 옵션으로
  /// 읽히지 않는다). `--codec=h264` 는 QuickTime 에서 바로 재생되는 코덱을 고정하고, `--mask=ignored` 는 스크린샷과 같은
  /// 사각 전체 화면, `--force` 는 호출한 쪽이 예약한 빈 파일을 덮어쓰게 한다 (없으면 있는 파일에 쓰지 않고 exit 17, 측정).
  static func recordVideo(udid: String, path: String) -> [String] {
    ["simctl", "io", udid, "recordVideo", "--codec=h264", "--mask=ignored", "--force", path]
  }

  /// create 성공 stdout("UUID\n")에서 UDID. 앞뒤 공백·개행을 자르고 UUID 형식이어야 한다. 아니면 nil.
  static func createdUDID(fromStdout data: Data) -> String? {
    guard let text = String(bytes: data, encoding: .utf8) else { return nil }
    return Self.validatedUDID(text.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  static func printDeveloperDirectory() -> [String] {
    ["-p"]
  }

  /// UUID 형식이면 대문자 UUID 문자열, 아니면 nil. 기기 이름이나 옵션("-h")이 인자로 해석되지 않게 한다.
  static func validatedUDID(_ raw: String) -> String? {
    UUID(uuidString: raw)?.uuidString
  }

  /// `environment(base:developerDirectory:)` 에 콘솔 실행용 두 값을 더한다:
  /// `NSUnbufferedIO=YES` 는 simctl 자신의 stdout 을 버퍼링하지 않게 해 실행 신호 줄이 곧바로 오게 하고(없으면 simctl 이 끝날 때 온다, 측정),
  /// `SIMCTL_CHILD_OS_ACTIVITY_DT_MODE=enable` 은 앱에 `OS_ACTIVITY_DT_MODE` 를 넘겨 Logger·os_log 도 콘솔로 오게 한다.
  static func consoleEnvironment(base: [String: String], developerDirectory: URL?) -> [String: String] {
    var environment = Self.environment(base: base, developerDirectory: developerDirectory)
    environment["NSUnbufferedIO"] = "YES"
    environment["SIMCTL_CHILD_OS_ACTIVITY_DT_MODE"] = "enable"
    return environment
  }

  /// 개발자 디렉터리가 있으면 `DEVELOPER_DIR` 로 넣고, 없으면 물려받은 `DEVELOPER_DIR` 도 지워 `xcode-select` 기본값을 쓴다.
  static func environment(base: [String: String], developerDirectory: URL?) -> [String: String] {
    var environment = base
    if let developerDirectory {
      environment["DEVELOPER_DIR"] = developerDirectory.path(percentEncoded: false)
    } else {
      environment["DEVELOPER_DIR"] = nil
    }
    return environment
  }
}
