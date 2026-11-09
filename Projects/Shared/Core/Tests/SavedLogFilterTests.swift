import Testing
@testable import Core

struct SavedLogFilterTests {
  static let condition = SavedLogFilter.Condition(kind: .contains, text: "error", isExcluded: false)

  static func conditions(_ count: Int) -> [SavedLogFilter.Condition] {
    Array(repeating: self.condition, count: count)
  }

  @Test("이름은 앞뒤 공백·개행을 잘라 저장한다")
  func trimsName() throws {
    let filter = try #require(SavedLogFilter(name: " \n 오류만\t ", conditions: [Self.condition], isCaseSensitive: true))

    #expect(filter.name == "오류만")
    #expect(filter.conditions == [Self.condition])
    #expect(filter.isCaseSensitive)
    #expect(SavedLogFilter.normalizedName("  a b  ") == "a b")
  }

  @Test("공백만인 이름은 emptyName, 40자는 되고 41자는 nameTooLong (Character 기준, ZWJ 이모지 40개는 된다)")
  func nameLength() {
    #expect(SavedLogFilter.nameProblem("") == .emptyName)
    #expect(SavedLogFilter.nameProblem(" \n\t ") == .emptyName)
    #expect(SavedLogFilter.nameProblem(String(repeating: "가", count: 40)) == nil)
    #expect(SavedLogFilter.nameProblem(" " + String(repeating: "a", count: 40) + " ") == nil)
    #expect(SavedLogFilter.nameProblem(String(repeating: "a", count: 41)) == .nameTooLong)
    let family = "👨‍👩‍👧‍👦"
    #expect(SavedLogFilter.nameProblem(String(repeating: family, count: 40)) == nil)
    #expect(SavedLogFilter.nameProblem(String(repeating: family, count: 41)) == .nameTooLong)
    #expect(SavedLogFilter(
      name: String(repeating: "a", count: 41),
      conditions: [Self.condition],
      isCaseSensitive: false
    ) == nil)
  }

  @Test("조건 0개는 noConditions, 20개는 되고 21개는 tooManyConditions")
  func conditionCount() {
    #expect(SavedLogFilter.conditionsProblem([]) == .noConditions)
    #expect(SavedLogFilter.conditionsProblem(Self.conditions(20)) == nil)
    #expect(SavedLogFilter.conditionsProblem(Self.conditions(21)) == .tooManyConditions)
    #expect(SavedLogFilter(name: "a", conditions: Self.conditions(20), isCaseSensitive: false) != nil)
    #expect(SavedLogFilter(name: "a", conditions: Self.conditions(21), isCaseSensitive: false) == nil)
    #expect(SavedLogFilter(name: "a", conditions: [], isCaseSensitive: false) == nil)
  }

  @Test("빈 글자 조건은 emptyText, 1000자는 되고 1001자는 textTooLong")
  func textLength() {
    func condition(_ text: String) -> SavedLogFilter.Condition {
      SavedLogFilter.Condition(kind: .regex, text: text, isExcluded: true)
    }
    #expect(SavedLogFilter.conditionsProblem([Self.condition, condition("")]) == .emptyText)
    #expect(SavedLogFilter.conditionsProblem([condition(String(repeating: "x", count: 1000))]) == nil)
    #expect(SavedLogFilter.conditionsProblem([condition(String(repeating: "x", count: 1001))]) == .textTooLong)
    #expect(SavedLogFilter.conditionsProblem([condition(" ")]) == nil)
  }

  @Test("문제는 이름 → 조건 수 → 글자 순서로 하나만 돌려준다")
  func problemOrder() {
    let long = SavedLogFilter.Condition(kind: .prefix, text: String(repeating: "x", count: 1001), isExcluded: false)
    let empty = SavedLogFilter.Condition(kind: .prefix, text: "", isExcluded: false)
    let tooMany = Array(repeating: empty, count: 21)
    let longName = String(repeating: "a", count: 41)

    #expect(SavedLogFilter.problem(name: " ", conditions: tooMany) == .emptyName)
    #expect(SavedLogFilter.problem(name: longName, conditions: tooMany) == .nameTooLong)
    #expect(SavedLogFilter.problem(name: "a", conditions: []) == .noConditions)
    #expect(SavedLogFilter.problem(name: "a", conditions: tooMany) == .tooManyConditions)
    #expect(SavedLogFilter.problem(name: "a", conditions: [long, empty]) == .emptyText)
    #expect(SavedLogFilter.problem(name: "a", conditions: [long]) == .textTooLong)
    #expect(SavedLogFilter.problem(name: "a", conditions: [Self.condition]) == nil)
  }

  @Test("같은 이름 판정은 대소문자와 앞뒤 공백을 무시한다")
  func sameName() {
    #expect(SavedLogFilter.isSameName("Errors", "errors"))
    #expect(SavedLogFilter.isSameName("  ERRORS\n", "errors"))
    #expect(SavedLogFilter.isSameName("오류만", " 오류만 "))
    #expect(!SavedLogFilter.isSameName("Errors", "Error"))
    #expect(!SavedLogFilter.isSameName("a b", "ab"))
  }

  @Test("Kind 저장 철자는 contains·prefix·regex 다")
  func kindSpelling() {
    #expect(SavedLogFilter.Kind.allCases.map(\.rawValue) == ["contains", "prefix", "regex"])
    #expect(SavedLogFilter.Kind(rawValue: "Contains") == nil)
  }
}
