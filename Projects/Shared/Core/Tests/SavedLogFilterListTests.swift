import Testing
@testable import Core

struct SavedLogFilterListTests {
  static func filter(_ name: String, text: String = "x") -> SavedLogFilter {
    SavedLogFilter(
      name: name,
      conditions: [SavedLogFilter.Condition(kind: .contains, text: text, isExcluded: false)],
      isCaseSensitive: false
    )!
  }

  static func many(_ count: Int) -> [SavedLogFilter?] {
    (0 ..< count).map { Self.filter("f\($0)") }
  }

  @Test("보이는 목록은 읽은 항목만 저장 순서대로, 같은 이름은 앞 것만")
  func visible() {
    let first = Self.filter("Errors", text: "1")
    let second = Self.filter("HTTP")
    let sameAsFirst = Self.filter("errors", text: "2")

    #expect(SavedLogFilterList.visible([nil, first, nil, second, sameAsFirst]) == [first, second])
    #expect(SavedLogFilterList.visible([nil, nil]).isEmpty)
  }

  @Test("새 이름은 끝에 붙인다")
  func appendsNewName() {
    let new = Self.filter("new")
    let items: [SavedLogFilter?] = [Self.filter("a"), nil]

    #expect(SavedLogFilterList.saveChange(new, replacingSameName: false, in: items) == .success(.append(new)))
    #expect(SavedLogFilterList.saveChange(new, replacingSameName: true, in: items) == .success(.append(new)))
  }

  @Test("같은 이름(대소문자 다름)을 덮어쓰지 않으면 sameName")
  func sameNameRefused() {
    let items: [SavedLogFilter?] = [Self.filter("Errors")]

    #expect(SavedLogFilterList
      .saveChange(Self.filter("ERRORS"), replacingSameName: false, in: items) == .failure(.sameName))
  }

  @Test("덮어쓰면 첫 자리를 바꾸고 다른 같은 이름 읽은 항목을 지운다 (읽지 못한 항목 자리는 그대로)")
  func replacesFirstAndRemovesOthers() {
    let new = Self.filter("errors", text: "new")
    let items: [SavedLogFilter?] = [
      Self.filter("a"),
      nil,
      Self.filter("Errors"),
      nil,
      Self.filter("ERRORS"),
      Self.filter("b"),
    ]

    let change = SavedLogFilterList.saveChange(new, replacingSameName: true, in: items)

    #expect(change == .success(.replace(index: 2, with: new, removing: [4])))
    let applied = (try? change.get())?.applied(to: items) { $0 }
    #expect(applied == [Self.filter("a"), nil, new, nil, Self.filter("b")])
  }

  @Test("보이는 목록 50개에 새 이름이면 limitReached, 49개면 붙인다 (읽지 못한 항목은 세지 않는다)")
  func limit() {
    let new = Self.filter("new")
    let fifty = Self.many(50)
    let fortyNineWithUnreadable = Self.many(49) + [nil, nil]
    let fiftyWithDuplicateName = Self.many(49) + [Self.filter("F0")]

    #expect(SavedLogFilterList.saveChange(new, replacingSameName: false, in: fifty) == .failure(.limitReached))
    #expect(SavedLogFilterList.saveChange(new, replacingSameName: true, in: fifty) == .failure(.limitReached))
    #expect(SavedLogFilterList
      .saveChange(new, replacingSameName: false, in: fortyNineWithUnreadable) == .success(.append(new)))
    #expect(SavedLogFilterList
      .saveChange(new, replacingSameName: false, in: fiftyWithDuplicateName) == .success(.append(new)))
  }

  @Test("50개여도 같은 이름 덮어쓰기는 된다")
  func replaceAtLimit() {
    let fifty = Self.many(50)
    let new = Self.filter("F10", text: "new")

    #expect(SavedLogFilterList.saveChange(new, replacingSameName: false, in: fifty) == .failure(.sameName))
    #expect(SavedLogFilterList.saveChange(new, replacingSameName: true, in: fifty) == .success(.replace(
      index: 10,
      with: new,
      removing: []
    )))
  }

  @Test("삭제는 같은 이름 읽은 항목을 모두 지우고, 없으면 nil")
  func remove() {
    let items: [SavedLogFilter?] = [Self.filter("Errors"), nil, Self.filter("b"), Self.filter("errors")]

    let change = SavedLogFilterList.removeChange(named: " ERRORS ", in: items)

    #expect(change == .remove([0, 3]))
    #expect(change?.applied(to: items) { $0 } == [nil, Self.filter("b")])
    #expect(SavedLogFilterList.removeChange(named: "none", in: items) == nil)
    #expect(SavedLogFilterList.removeChange(named: "x", in: [nil]) == nil)
  }

  @Test("변경 적용은 고치지 않는 자리의 원소를 그대로 두고 순서를 지킨다 (append·replace·remove)")
  func appliesToRawItems() {
    let raw = ["r0", "r1", "r2", "r3"]
    let new = Self.filter("new")
    let encode: (SavedLogFilter) -> String = { "w:\($0.name)" }

    #expect(SavedLogFilterList.Change.append(new).applied(to: raw, encode: encode) == ["r0", "r1", "r2", "r3", "w:new"])
    #expect(
      SavedLogFilterList.Change.replace(index: 1, with: new, removing: [2, 3]).applied(to: raw, encode: encode)
        == ["r0", "w:new"]
    )
    #expect(
      SavedLogFilterList.Change.replace(index: 2, with: new, removing: []).applied(to: raw, encode: encode)
        == ["r0", "r1", "w:new", "r3"]
    )
    #expect(SavedLogFilterList.Change.remove([0, 2]).applied(to: raw, encode: encode) == ["r1", "r3"])
    #expect(SavedLogFilterList.Change.remove([]).applied(to: raw, encode: encode) == raw)
    #expect(SavedLogFilterList.Change.append(new).applied(to: [], encode: encode) == ["w:new"])
  }
}
