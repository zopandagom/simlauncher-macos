import Core
import Foundation

/// 저장된 `LogFilters` 값 해석 (docs/CATALOG.md 9절). 관리자가 `defaults write` 로 넣은 값은 형식이 다를 수 있다.
/// 항목 형식: `name`(문자열), `caseSensitive`(Bool, 없으면 거짓), `conditions`(사전 배열:
/// `kind`("contains"·"prefix"·"regex"), `text`(문자열), `excluded`(Bool, 없으면 거짓)). 모르는 키는 무시한다.
enum LogFilterValue {
  static let nameKey = "name"
  static let caseSensitiveKey = "caseSensitive"
  static let conditionsKey = "conditions"
  static let kindKey = "kind"
  static let textKey = "text"
  static let excludedKey = "excluded"

  /// 배열이면 항목 그대로, 그 밖(nil·문자열·사전·숫자)은 빈 배열.
  static func items(from value: Any?) -> [Any] {
    value as? [Any] ?? []
  }

  /// 형식과 Core 규칙(`SavedLogFilter.init?`)을 통과하면 값, 아니면 nil (읽을 수 없는 항목).
  /// 이름은 앞뒤 공백을 잘라 읽는다. 정규식이 맞는지는 보지 않는다 (불러온 뒤 로그 창이 알린다).
  static func filter(from item: Any) -> SavedLogFilter? {
    guard
      let dictionary = item as? [String: Any],
      let name = dictionary[self.nameKey] as? String,
      let isCaseSensitive = self.bool(from: dictionary[self.caseSensitiveKey]),
      let rawConditions = dictionary[self.conditionsKey] as? [Any]
    else {
      return nil
    }
    var conditions: [SavedLogFilter.Condition] = []
    conditions.reserveCapacity(rawConditions.count)
    for rawCondition in rawConditions {
      guard let condition = self.condition(from: rawCondition) else {
        return nil
      }
      conditions.append(condition)
    }
    return SavedLogFilter(name: name, conditions: conditions, isCaseSensitive: isCaseSensitive)
  }

  /// Bool 칸. 키 없음(nil) → 거짓. `as? Bool` 이 값을 주면(CFBoolean, 숫자 0·1) 그 값.
  /// 문자열이면 대소문자 무시 `yes`·`true`·`1` → 참, `no`·`false`·`0` → 거짓 (옛 형식 `defaults write` 는 모든 값을 문자열로 넣는다).
  /// 그 밖(숫자 2, 다른 문자열, 배열 등)은 nil (항목을 읽지 못한다).
  static func bool(from value: Any?) -> Bool? {
    guard let value else {
      return false
    }
    if let string = value as? String {
      switch string.lowercased() {
      case "yes", "true", "1":
        return true
      case "no", "false", "0":
        return false
      default:
        return nil
      }
    }
    return value as? Bool
  }

  /// 쓰기 형식. 세 Bool 칸과 kind 철자를 항상 쓴다.
  static func plist(for filter: SavedLogFilter) -> [String: Any] {
    [
      self.nameKey: filter.name,
      self.caseSensitiveKey: filter.isCaseSensitive,
      self.conditionsKey: filter.conditions.map { condition -> [String: Any] in
        [
          self.kindKey: condition.kind.rawValue,
          self.textKey: condition.text,
          self.excludedKey: condition.isExcluded,
        ]
      },
    ]
  }

  private static func condition(from item: Any) -> SavedLogFilter.Condition? {
    guard
      let dictionary = item as? [String: Any],
      let rawKind = dictionary[self.kindKey] as? String,
      let kind = SavedLogFilter.Kind(rawValue: rawKind),
      let text = dictionary[self.textKey] as? String,
      let isExcluded = self.bool(from: dictionary[self.excludedKey])
    else {
      return nil
    }
    return SavedLogFilter.Condition(kind: kind, text: text, isExcluded: isExcluded)
  }
}
