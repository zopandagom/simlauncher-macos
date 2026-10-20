import Foundation

/// 실행할 명령과 인자·환경 (순수).
enum SimctlCommand {
  static let xcrun = URL(filePath: "/usr/bin/xcrun")
  static let xcodeSelect = URL(filePath: "/usr/bin/xcode-select")
  static let open = URL(filePath: "/usr/bin/open")

  static func list() -> [String] {
    ["simctl", "list", "-j"]
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

  /// `udid` 는 `validatedUDID(_:)` 를 거친 값, `url` 은 `DeepLink.url.absoluteString`(스킴으로 시작)만 넘긴다.
  /// openurl 은 기기 뒤 인자를 옵션으로 읽지 않고 `--` 도 URL 로 받으므로(-50) 붙이지 않는다.
  static func openURL(udid: String, url: String) -> [String] {
    ["simctl", "openurl", udid, url]
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
