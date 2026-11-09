import Core
import Foundation
import Testing
@testable import PreferencesImpl

/// 정수 표기 Bool 은 `NSNumber(value:)` 로 만든다 (Swift `Int` 를 `Any` 에 넣으면 `as? Bool` 이 nil 이다, 설계 1(d) 실측).
struct LogFilterValueTests {
  static func condition(
    kind: Any = "contains",
    text: Any = "error",
    excluded: Any? = false
  ) -> [String: Any] {
    var condition: [String: Any] = ["kind": kind, "text": text]
    condition["excluded"] = excluded
    return condition
  }

  static func item(
    name: Any = "오류만",
    caseSensitive: Any? = false,
    conditions: Any? = [Self.condition()]
  ) -> [String: Any] {
    var item: [String: Any] = ["name": name]
    item["caseSensitive"] = caseSensitive
    item["conditions"] = conditions
    return item
  }

  static func expected(
    name: String = "오류만",
    _ conditions: [SavedLogFilter.Condition] = [.init(kind: .contains, text: "error", isExcluded: false)],
    isCaseSensitive: Bool = false
  ) throws -> SavedLogFilter {
    try #require(SavedLogFilter(name: name, conditions: conditions, isCaseSensitive: isCaseSensitive))
  }

  @Test("바른 사전을 읽는다 (CFBoolean·숫자 0·1 Bool)")
  func readsValidItem() throws {
    let item = Self.item(
      name: "HTTP",
      caseSensitive: true,
      conditions: [
        Self.condition(kind: "regex", text: #"status=[45]\d\d"#, excluded: NSNumber(value: 0)),
        Self.condition(kind: "prefix", text: "net", excluded: NSNumber(value: 1)),
        Self.condition(kind: "contains", text: "health", excluded: NSNumber(value: true)),
      ]
    )

    let expected = try Self.expected(
      name: "HTTP",
      [
        .init(kind: .regex, text: #"status=[45]\d\d"#, isExcluded: false),
        .init(kind: .prefix, text: "net", isExcluded: true),
        .init(kind: .contains, text: "health", isExcluded: true),
      ],
      isCaseSensitive: true
    )
    #expect(LogFilterValue.filter(from: item) == expected)
    #expect(LogFilterValue.filter(from: Self.item(caseSensitive: NSNumber(value: 1)))?.isCaseSensitive == true)
    #expect(LogFilterValue.filter(from: NSDictionary(dictionary: item)) == expected)
  }

  @Test("caseSensitive·excluded 가 없으면 거짓")
  func missingBoolsAreFalse() throws {
    let item = Self.item(caseSensitive: nil, conditions: [Self.condition(excluded: nil)])
    #expect(try LogFilterValue.filter(from: item) == Self.expected())
  }

  @Test(
    "Bool 문자열 표기 YES·no·1·0·true·FALSE 를 읽는다",
    arguments: [("YES", true), ("no", false), ("1", true), ("0", false), ("true", true), ("FALSE", false)]
  )
  func stringBools(raw: String, value: Bool) {
    #expect(LogFilterValue.bool(from: raw) == value)
    let item = Self.item(caseSensitive: raw, conditions: [Self.condition(excluded: raw)])
    let filter = LogFilterValue.filter(from: item)
    #expect(filter?.isCaseSensitive == value)
    #expect(filter?.conditions.first?.isExcluded == value)
  }

  @Test("Bool 이 숫자 2·다른 문자열·배열이면 항목을 읽지 못한다")
  func invalidBools() {
    let invalid: [Any] = [NSNumber(value: 2), NSNumber(value: 0.5), "maybe", "", ["YES"], Data([1])]
    for value in invalid {
      #expect(LogFilterValue.bool(from: value) == nil)
      #expect(LogFilterValue.filter(from: Self.item(caseSensitive: value)) == nil)
      #expect(LogFilterValue.filter(from: Self.item(conditions: [Self.condition(excluded: value)])) == nil)
    }
    #expect(LogFilterValue.bool(from: nil) == false)
  }

  @Test("항목이 문자열·숫자·Data·Date·빈 사전이면 읽지 못한다")
  func nonDictionaryItems() {
    let items: [Any] = [
      "hello",
      NSNumber(value: 5),
      Data([1]),
      Date(timeIntervalSince1970: 0),
      [String: Any](),
      NSDictionary(),
    ]
    for item in items {
      #expect(LogFilterValue.filter(from: item) == nil)
    }
  }

  @Test("이름이 숫자·빈 문자열·41자면 읽지 못하고, 앞뒤 공백은 잘라 읽는다")
  func names() {
    #expect(LogFilterValue.filter(from: Self.item(name: NSNumber(value: 7))) == nil)
    #expect(LogFilterValue.filter(from: Self.item(name: "")) == nil)
    #expect(LogFilterValue.filter(from: Self.item(name: "   ")) == nil)
    #expect(LogFilterValue.filter(from: Self.item(name: String(repeating: "a", count: 41))) == nil)
    #expect(LogFilterValue.filter(from: Self.item(name: String(repeating: "a", count: 40))) != nil)
    #expect(LogFilterValue.filter(from: Self.item(name: "  오류만 \n"))?.name == "오류만")
  }

  @Test("conditions 가 없음·배열 아님·빈 배열·21개·사전 아닌 원소면 읽지 못한다")
  func conditions() {
    #expect(LogFilterValue.filter(from: Self.item(conditions: nil)) == nil)
    #expect(LogFilterValue.filter(from: Self.item(conditions: Self.condition())) == nil)
    #expect(LogFilterValue.filter(from: Self.item(conditions: "error")) == nil)
    #expect(LogFilterValue.filter(from: Self.item(conditions: [Any]())) == nil)
    #expect(LogFilterValue.filter(from: Self.item(conditions: Array(repeating: Self.condition(), count: 21))) == nil)
    #expect(LogFilterValue.filter(from: Self.item(conditions: Array(repeating: Self.condition(), count: 20))) != nil)
    #expect(LogFilterValue.filter(from: Self.item(conditions: [Self.condition(), "error"] as [Any])) == nil)
  }

  @Test("kind 가 모르는 철자·대문자거나 text 가 숫자·빈 문자열·1001자면 읽지 못한다")
  func conditionFields() {
    for kind in ["fuzzy", "Contains", "REGEX", ""] {
      #expect(LogFilterValue.filter(from: Self.item(conditions: [Self.condition(kind: kind)])) == nil)
    }
    #expect(LogFilterValue.filter(from: Self.item(conditions: [Self.condition(kind: NSNumber(value: 1))])) == nil)
    #expect(LogFilterValue.filter(from: Self.item(conditions: [Self.condition(text: NSNumber(value: 42))])) == nil)
    #expect(LogFilterValue.filter(from: Self.item(conditions: [Self.condition(text: "")])) == nil)
    let long = String(repeating: "x", count: 1001)
    #expect(LogFilterValue.filter(from: Self.item(conditions: [Self.condition(text: long)])) == nil)
    let limit = String(repeating: "x", count: 1000)
    #expect(LogFilterValue.filter(from: Self.item(conditions: [Self.condition(text: limit)])) != nil)
    var missingKind = Self.condition()
    missingKind["kind"] = nil
    #expect(LogFilterValue.filter(from: Self.item(conditions: [missingKind])) == nil)
  }

  @Test("모르는 키는 무시한다")
  func ignoresUnknownKeys() throws {
    var item = Self.item()
    item["extra"] = NSNumber(value: 1.5)
    var condition = Self.condition()
    condition["note"] = "memo"
    item["conditions"] = [condition]

    #expect(try LogFilterValue.filter(from: item) == Self.expected())
  }

  @Test("쓰기 형식의 키 이름·타입이 고정이고 다시 읽으면 같은 값이다")
  func writeFormat() throws {
    let filter = try Self.expected(
      name: "HTTP",
      [
        .init(kind: .regex, text: "a", isExcluded: false),
        .init(kind: .prefix, text: "b", isExcluded: true),
      ],
      isCaseSensitive: true
    )

    let plist = LogFilterValue.plist(for: filter)

    #expect(Set(plist.keys) == ["name", "caseSensitive", "conditions"])
    #expect(plist["name"] as? String == "HTTP")
    #expect(plist["caseSensitive"] as? Bool == true)
    let conditions = try #require(plist["conditions"] as? [[String: Any]])
    #expect(conditions.count == 2)
    #expect(conditions.allSatisfy { Set($0.keys) == ["kind", "text", "excluded"] })
    #expect(conditions[0]["kind"] as? String == "regex")
    #expect(conditions[0]["text"] as? String == "a")
    #expect(conditions[0]["excluded"] as? Bool == false)
    #expect(conditions[1]["kind"] as? String == "prefix")
    #expect(conditions[1]["excluded"] as? Bool == true)
    #expect(PropertyListSerialization.propertyList(plist, isValidFor: .binary))
    #expect(LogFilterValue.filter(from: plist) == filter)
  }

  @Test("키 값이 배열이 아니면 항목 없음")
  func itemsFromNonArray() {
    #expect(LogFilterValue.items(from: nil).isEmpty)
    #expect(LogFilterValue.items(from: "오류만").isEmpty)
    #expect(LogFilterValue.items(from: NSNumber(value: 1)).isEmpty)
    #expect(LogFilterValue.items(from: Self.item()).isEmpty)
    #expect(LogFilterValue.items(from: [Self.item(), "x"] as [Any]).count == 2)
    #expect(LogFilterValue.items(from: NSArray(array: ["x"])).count == 1)
  }
}
