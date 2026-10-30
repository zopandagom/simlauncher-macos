import Foundation
import Testing
@testable import Core

enum Fixture {
  static func data(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
  }
}

/// 정수 밀리초. 소수 초가 든 `Date` 를 리터럴 `Date(timeIntervalSince1970:)` 과 `==` 로 비교하면 부동소수 차이로 틀린다.
func milliseconds(_ date: Date) -> Int64 {
  Int64((date.timeIntervalSince1970 * 1000).rounded())
}

/// 테스트용 카탈로그 JSON 을 만든다. 값은 JSON 문법 그대로의 문자열이다 (`#""a""#`, `"1"`, `"null"`).
enum CatalogText {
  /// 앱·버전 기본 필드에서 `replacing` 의 키는 값을 바꾸고(없던 키는 끝에 붙인다), `removing` 의 키는 뺀다.
  struct Overrides {
    var replacing: [String: String] = [:]
    var removing: Set<String> = []
  }

  static let defaultCreatedAt = "2026-10-21T04:08:49Z"

  static func catalog(_ apps: [String], schemaVersion: Int = 1) -> Data {
    Data(#"{"schemaVersion":\#(schemaVersion),"apps":[\#(apps.joined(separator: ","))]}"#.utf8)
  }

  static func app(
    id: String = "a",
    versions: [String] = [],
    replacing: [String: String] = [:],
    removing: Set<String> = []
  ) -> String {
    let fields: [(key: String, value: String)] = [
      ("id", self.quoted(id)),
      ("name", self.quoted("App \(id)")),
      ("versions", "[\(versions.joined(separator: ","))]"),
    ]
    return self.object(fields, Overrides(replacing: replacing, removing: removing))
  }

  static func version(
    id: String = "v1",
    createdAt: String = Self.defaultCreatedAt,
    replacing: [String: String] = [:],
    removing: Set<String> = []
  ) -> String {
    let fields: [(key: String, value: String)] = [
      ("id", self.quoted(id)),
      ("name", self.quoted("Version \(id)")),
      ("createdAt", self.quoted(createdAt)),
      ("buildURL", self.quoted("https://example.com/\(id).zip")),
    ]
    return self.object(fields, Overrides(replacing: replacing, removing: removing))
  }

  /// Swift 문자열을 JSON 문자열 리터럴로 바꾼다.
  static func quoted(_ value: String) -> String {
    var escaped = ""
    for scalar in value.unicodeScalars {
      switch scalar {
      case "\"": escaped += "\\\""
      case "\\": escaped += "\\\\"
      case "\n": escaped += "\\n"
      case "\t": escaped += "\\t"
      default: escaped.unicodeScalars.append(scalar)
      }
    }
    return "\"\(escaped)\""
  }

  /// 가장 안쪽 값(`0`)이 최상위 필드 값에서 `depth` 단계가 되도록 객체 또는 배열을 겹친 JSON 값.
  static func nested(depth: Int, objects: Bool) -> String {
    let open = objects ? #"{"a":"# : "["
    let close = objects ? "}" : "]"
    let opening = String(repeating: open, count: depth - 1)
    let closing = String(repeating: close, count: depth - 1)
    return "\(opening)0\(closing)"
  }

  private static func object(_ fields: [(key: String, value: String)], _ overrides: Overrides) -> String {
    let known = Set(fields.map(\.key))
    var parts: [String] = []
    for field in fields where !overrides.removing.contains(field.key) {
      let value = overrides.replacing[field.key] ?? field.value
      parts.append("\(self.quoted(field.key)):\(value)")
    }
    for key in overrides.replacing.keys.sorted() where !known.contains(key) {
      parts.append("\(self.quoted(key)):\(overrides.replacing[key] ?? "null")")
    }
    return "{\(parts.joined(separator: ","))}"
  }
}

/// 해석이 던진 문제. 통과하면 nil.
func catalogProblem(_ data: Data) -> BuildCatalogProblem? {
  do {
    _ = try BuildCatalog(jsonData: data)
    return nil
  } catch {
    return error
  }
}

/// 문제 위치. 버전 인덱스를 주지 않으면 앱 위치.
func catalogPosition(
  app appIndex: Int,
  _ appID: String?,
  version versionIndex: Int? = nil,
  _ versionID: String? = nil
) -> BuildCatalogProblem.Position {
  BuildCatalogProblem.Position(appIndex: appIndex, appID: appID, versionIndex: versionIndex, versionID: versionID)
}

/// 정수 마이크로초.
func microseconds(_ date: Date) -> Int64 {
  Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
}
