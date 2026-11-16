import Foundation
import Testing
@testable import SettingsFeature

/// 복수형이 필요한 키(레포의 `.github/scripts/xcstrings-plural-keys.txt` 중 이 모듈 줄)는 en 값에 `variations.plural` 이나
/// `substitutions` 가 있고, 컴파일된 en 표로 개수 1 과 2 를 넣으면 단수·복수 낱말로 갈린다. 테스트는 스킴에서 ko 로 돌므로
/// en 표는 리소스 번들의 `en.lproj` 를 직접 열어 읽는다. 키 목록은 검사 스크립트(`make strings-check`)와 같은 파일을 읽는다.
struct SettingsEnglishPluralTests {
  static let module = "Settings"

  @Test("복수형 목록의 키는 en 에 복수형이 있고, 개수 1·2 의 결과가 단수·복수 낱말로 갈린다")
  func pluralKeysVaryByCount() throws {
    let keys = try EnglishPluralCheck.keys(module: Self.module, testFile: #filePath)
    #expect(!keys.isEmpty)
    let catalog = try EnglishPluralCheck.catalog(testFile: #filePath)
    let english = try EnglishPluralCheck.englishBundle(Bundle.module)
    for key in keys {
      try EnglishPluralCheck.check(key: key, catalog: catalog, english: english)
    }
  }
}

/// 복수형 확인 도구. Feature 테스트끼리 코드를 나누지 않으므로 모듈마다 같은 내용을 둔다
/// (Launcher·AndroidDevices·Settings·DeviceLog 의 `<모듈>EnglishPluralTests.swift`).
enum EnglishPluralCheck {
  static let locale = Locale(identifier: "en_US")

  /// 레포의 복수형 목록에서 이 모듈의 키. `#` 로 시작하는 줄과 빈 줄은 건너뛴다.
  static func keys(module: String, testFile: String) throws -> [String] {
    let url = URL(filePath: testFile)
      .deletingLastPathComponent()
      .appending(path: "../../../../.github/scripts/xcstrings-plural-keys.txt")
      .standardized
    let text = try String(contentsOf: url, encoding: .utf8)
    return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
      guard !line.hasPrefix("#"), !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
      let parts = line.split(separator: "\t", maxSplits: 1)
      guard parts.count == 2, parts[0] == module else { return nil }
      return String(parts[1])
    }
  }

  /// 이 모듈 원본 String Catalog 의 `strings`.
  static func catalog(testFile: String) throws -> [String: Any] {
    let url = URL(filePath: testFile)
      .deletingLastPathComponent()
      .appending(path: "../Sources/Localizable.xcstrings")
      .standardized
    let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    return try #require(root["strings"] as? [String: Any])
  }

  /// 리소스 번들의 `en.lproj`.
  static func englishBundle(_ bundle: Bundle) throws -> Bundle {
    let path = try #require(bundle.path(forResource: "en", ofType: "lproj"))
    return try #require(Bundle(path: path))
  }

  /// 키 하나: en 항목의 복수형 구조를 찾고, 복수형 인자에 1·2 를 넣은 결과가 그 변형의 낱말을 담는지 본다.
  static func check(key: String, catalog: [String: Any], english: Bundle) throws {
    let entry = try #require(catalog[key] as? [String: Any], "카탈로그에 없는 키: \(key)")
    let localizations = try #require(entry["localizations"] as? [String: Any])
    let englishEntry = try #require(localizations["en"] as? [String: Any], "en 값이 없다: \(key)")
    let specifiers = self.formatSpecifiers(key)
    let format = english.localizedString(forKey: key, value: nil, table: nil)
    #expect(format != key, "en 표에 없다: \(key)")

    if let plural = (englishEntry["variations"] as? [String: Any])?["plural"] as? [String: Any] {
      let countArguments = specifiers.filter { $0 == "lld" }.count
      #expect(countArguments == 1, "\(key)")
      let one = try #require(value(plural["one"]), "\(key)")
      let other = try #require(value(plural["other"]), "\(key)")
      #expect(one != other, "\(key)")
      let countIndex = try #require(specifiers.firstIndex(of: "lld"), "\(key)")
      for (count, form) in [(1, one), (2, other)] {
        let args = self.arguments(specifiers, pluralArgument: countIndex + 1, count: count)
        let expected = String(format: form, locale: locale, arguments: args)
        #expect(String(format: format, locale: self.locale, arguments: args) == expected, "\(key) (\(count))")
      }
    } else {
      let substitutions = try #require(englishEntry["substitutions"] as? [String: Any], "복수형이 없다: \(key)")
      #expect(substitutions.count == 1, "\(key)")
      let substitution = try #require(substitutions.values.first as? [String: Any])
      let argNum = try #require(substitution["argNum"] as? Int)
      let pluralSpecifier = specifiers.indices.contains(argNum - 1) ? specifiers[argNum - 1] : nil
      #expect(pluralSpecifier == "lld", "\(key)")
      let plural = try #require((substitution["variations"] as? [String: Any])?["plural"] as? [String: Any])
      let one = try #require(value(plural["one"])).replacingOccurrences(of: "%arg", with: "1")
      let other = try #require(value(plural["other"])).replacingOccurrences(of: "%arg", with: "2")
      let singular = String(
        format: format,
        locale: locale,
        arguments: arguments(specifiers, pluralArgument: argNum, count: 1)
      )
      let plural2 = String(
        format: format,
        locale: locale,
        arguments: arguments(specifiers, pluralArgument: argNum, count: 2)
      )
      #expect(singular != plural2, "\(key)")
      #expect(singular.contains(one), "\(key): \(singular)")
      #expect(plural2.contains(other), "\(key): \(plural2)")
    }
  }

  /// 키(ko 원문)의 지정자 종류를 인자 순서대로 (`@`·`lld`. 지금 카탈로그에는 이 둘뿐이다).
  static func formatSpecifiers(_ key: String) -> [String] {
    key.matches(of: /%(lld|@)/).map { String($0.output.1) }
  }

  /// 복수형 인자(1부터 센 번호)에 `count`, 다른 정수 인자에 7, 문자열 인자에 "x".
  static func arguments(_ specifiers: [String], pluralArgument: Int, count: Int) -> [CVarArg] {
    specifiers.enumerated().map { index, specifier -> CVarArg in
      if specifier == "@" {
        return "x"
      }
      return index + 1 == pluralArgument ? count : 7
    }
  }

  static func value(_ variant: Any?) -> String? {
    ((variant as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
  }
}
