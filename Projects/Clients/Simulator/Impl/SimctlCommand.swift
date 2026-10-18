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
