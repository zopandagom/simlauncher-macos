import Foundation
import Testing
@testable import LauncherFeature

/// 카탈로그 문구의 문맥 없는 조각(위치·필드 설명·주소 이유·60초·연결 끊김)은 Settings 와 같은 키·값으로 Launcher 에도 둔다
/// (Feature 끼리 의존하지 않기 위해, ARCHITECTURE §4 화면 문자열 행). 이 테스트는 Settings 원본 String Catalog 를
/// 소스 경로(`settingsCatalog`)로 읽어, Launcher 문구 함수의 결과가 그 값으로
/// 만든 문구와 같은지 본다. 한쪽만 고치면 실패한다: Launcher 만 바꾸면 결과가 Settings 값과 다르고, Settings 만 바꾸면
/// 그 키가 Settings 에 없다. 두 원본 카탈로그의 en 항목(복수형 포함 JSON 값 전체)도 같아야 한다.
struct CatalogFragmentSyncTests {
  /// 이 파일 기준의 Settings String Catalog 경로.
  static let settingsCatalog = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "../../Settings/Sources/Localizable.xcstrings")
    .standardized

  /// 이 모듈 String Catalog 경로.
  static let launcherCatalog = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "../Sources/Localizable.xcstrings")
    .standardized

  /// String Catalog(JSON)의 키 → ko 값.
  static func koreanTable(at url: URL) throws -> [String: String] {
    let data = try Data(contentsOf: url)
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let strings = try #require(root["strings"] as? [String: Any])
    var table: [String: String] = [:]
    for (key, entry) in strings {
      let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any]
      let unit = (localizations?["ko"] as? [String: Any])?["stringUnit"] as? [String: Any]
      if let value = unit?["value"] as? String {
        table[key] = value
      }
    }
    return table
  }

  /// String Catalog(JSON)의 키 → en 항목(복수형·substitutions 를 포함한 JSON 값 전체).
  static func englishTable(at url: URL) throws -> [String: NSDictionary] {
    let data = try Data(contentsOf: url)
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let strings = try #require(root["strings"] as? [String: Any])
    var table: [String: NSDictionary] = [:]
    for (key, entry) in strings {
      let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any]
      if let english = localizations?["en"] as? NSDictionary {
        table[key] = english
      }
    }
    return table
  }

  @Test("Settings 와 같은 키로 둔 조각 25개가 Settings 원본에 있고, Launcher 문구 함수의 결과가 그 값으로 만든 문구와 같고, en 값도 같다")
  func fragmentsMatchSettingsCatalog() throws {
    let table = try Self.koreanTable(at: Self.settingsCatalog)
    let settingsEnglish = try Self.englishTable(at: Self.settingsCatalog)
    let launcherEnglish = try Self.englishTable(at: Self.launcherCatalog)
    #expect(!table.isEmpty)
    let checks = CatalogTextCatalog.fragmentChecks(table)

    #expect(checks.map(\.key) == CatalogTextCatalog.fragmentKeys)
    #expect(Set(CatalogTextCatalog.fragmentKeys).count == 25)
    for check in checks {
      #expect(table[check.key] != nil, "Settings 에 없는 키: \(check.key)")
      #expect(check.actual == check.expected, "\(check.key)")
      #expect(
        settingsEnglish[check.key] != nil && launcherEnglish[check.key] == settingsEnglish[check.key],
        "en 값이 Settings 와 다르거나 없다: \(check.key)"
      )
    }
  }
}
