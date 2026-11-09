import Core
import PreferencesInterface
import Testing
@testable import PreferencesImpl

struct PreferencesClientImplLogFilterTests {
  static func filter(_ name: String, text: String = "x") -> SavedLogFilter {
    SavedLogFilter(
      name: name,
      conditions: [SavedLogFilter.Condition(kind: .contains, text: text, isExcluded: false)],
      isCaseSensitive: false
    )!
  }

  static func original(_ name: String, text: String = "x") -> StoredLogFilterItem {
    .filter(self.filter(name, text: text), tag: "original")
  }

  static func written(_ name: String, text: String = "x") -> StoredLogFilterItem {
    .filter(self.filter(name, text: text), tag: "written")
  }

  static func fixture(
    _ items: [StoredLogFilterItem] = [],
    isForced: Bool = false
  ) -> (PreferencesClientImpl, InMemoryPreferenceStore) {
    let store = InMemoryPreferenceStore()
    store.replaceLogFilters(items, isForced: isForced)
    return (PreferencesClientImpl(store: store), store)
  }

  static func many(_ count: Int) -> [StoredLogFilterItem] {
    (0 ..< count).map { Self.original("f\($0)") }
  }

  @Test("빈 저장소는 빈 목록, 잠기지 않음")
  func emptyStore() {
    let (client, _) = Self.fixture()
    #expect(client.savedLogFilters() == .empty)
  }

  @Test("강제된 키는 목록을 읽고 잠김으로 알린다")
  func forcedReadsLocked() {
    let (client, _) = Self.fixture([Self.original("a"), .unreadable("broken"), Self.original("A")], isForced: true)
    #expect(client.savedLogFilters() == SavedLogFilterSetting(filters: [Self.filter("a")], isLocked: true))
  }

  @Test("저장하면 끝에 붙이고 저장 뒤 목록을 돌려준다 (쓰기 1번)")
  func saveAppends() throws {
    let (client, store) = Self.fixture([Self.original("a")])

    let setting = try client.saveLogFilter(Self.filter("b"), replacingSameName: false)

    #expect(setting == SavedLogFilterSetting(filters: [Self.filter("a"), Self.filter("b")], isLocked: false))
    #expect(store.logFilterItems == [Self.original("a"), Self.written("b")])
    #expect(store.logFiltersSetCount == 1)
  }

  @Test("읽지 못한 항목은 목록에 없고, 저장·덮어쓰기·삭제 뒤에도 같은 자리에 원래 값 그대로")
  func keepsUnreadableItems() throws {
    let (client, store) = Self.fixture([.unreadable("u0"), Self.original("a"), .unreadable("u2"), Self.original("b")])
    #expect(client.savedLogFilters().filters == [Self.filter("a"), Self.filter("b")])

    _ = try client.saveLogFilter(Self.filter("c"), replacingSameName: false)
    #expect(store.logFilterItems == [
      .unreadable("u0"), Self.original("a"), .unreadable("u2"), Self.original("b"), Self.written("c"),
    ])

    _ = try client.saveLogFilter(Self.filter("A", text: "new"), replacingSameName: true)
    #expect(store.logFilterItems == [
      .unreadable("u0"), Self.written("A", text: "new"), .unreadable("u2"), Self.original("b"), Self.written("c"),
    ])

    let setting = try client.removeLogFilter(named: "b")
    #expect(store.logFilterItems == [
      .unreadable("u0"),
      Self.written("A", text: "new"),
      .unreadable("u2"),
      Self.written("c"),
    ])
    #expect(setting.filters == [Self.filter("A", text: "new"), Self.filter("c")])
  }

  @Test("고치지 않은 읽은 항목은 다시 쓰지 않고 원본 그대로")
  func untouchedItemsStayOriginal() throws {
    let (client, store) = Self.fixture([Self.original("a"), Self.original("b"), Self.original("c")])

    _ = try client.saveLogFilter(Self.filter("b", text: "new"), replacingSameName: true)

    #expect(store.logFilterItems == [Self.original("a"), Self.written("b", text: "new"), Self.original("c")])
  }

  @Test("같은 이름(대소문자 다름)을 덮어쓰지 않으면 duplicate, 쓰지 않는다")
  func duplicateRefused() {
    let (client, store) = Self.fixture([Self.original("Errors")])

    #expect(throws: PreferencesError.duplicate) {
      try client.saveLogFilter(Self.filter(" errors "), replacingSameName: false)
    }
    #expect(store.logFiltersSetCount == 0)
    #expect(store.logFilterItems == [Self.original("Errors")])
  }

  @Test("덮어쓰면 첫 자리를 새 값(새 이름 표기 포함)으로 바꾸고 다른 같은 이름 항목을 지운다")
  func replaceRewritesFirstAndRemovesOthers() throws {
    let (client, store) = Self.fixture([
      Self.original("x"), Self.original("Errors", text: "1"), .unreadable("u"), Self.original("ERRORS", text: "2"),
    ])

    let setting = try client.saveLogFilter(Self.filter("errors", text: "new"), replacingSameName: true)

    #expect(store.logFilterItems == [Self.original("x"), Self.written("errors", text: "new"), .unreadable("u")])
    #expect(setting.filters.map(\.name) == ["x", "errors"])
    #expect(store.logFiltersSetCount == 1)
  }

  @Test("덮어쓰기인데 같은 이름이 바깥에서 지워졌으면 끝에 붙인다")
  func replaceAfterOutsideRemovalAppends() throws {
    let (client, store) = Self.fixture([Self.original("a"), Self.original("b")])
    _ = client.savedLogFilters()
    store.replaceLogFilters([Self.original("b")], isForced: false)

    let setting = try client.saveLogFilter(Self.filter("a", text: "new"), replacingSameName: true)

    #expect(store.logFilterItems == [Self.original("b"), Self.written("a", text: "new")])
    #expect(setting.filters.map(\.name) == ["b", "a"])
  }

  @Test("50개에 새 이름이면 limitReached, 쓰지 않는다")
  func limitReached() throws {
    let (client, store) = Self.fixture(Self.many(50) + [.unreadable("u")])

    #expect(throws: PreferencesError.limitReached) {
      try client.saveLogFilter(Self.filter("new"), replacingSameName: false)
    }
    #expect(throws: PreferencesError.limitReached) {
      try client.saveLogFilter(Self.filter("new"), replacingSameName: true)
    }
    #expect(store.logFiltersSetCount == 0)

    store.replaceLogFilters(Self.many(49) + [.unreadable("u")], isForced: false)
    #expect(try client.saveLogFilter(Self.filter("new"), replacingSameName: false).filters.count == 50)
  }

  @Test("50개여도 같은 이름은 덮어쓰기로 저장된다 (개수 그대로)")
  func replaceAtLimit() throws {
    let (client, store) = Self.fixture(Self.many(50))

    #expect(throws: PreferencesError.duplicate) {
      try client.saveLogFilter(Self.filter("F3"), replacingSameName: false)
    }
    let setting = try client.saveLogFilter(Self.filter("F3", text: "new"), replacingSameName: true)

    #expect(setting.filters.count == 50)
    #expect(setting.filters[3] == Self.filter("F3", text: "new"))
    #expect(store.logFilterItems[3] == Self.written("F3", text: "new"))
  }

  @Test("잠겼으면 저장·삭제 모두 locked, 쓰지 않는다")
  func lockedRefusesWrites() {
    let (client, store) = Self.fixture([Self.original("a")], isForced: true)

    #expect(throws: PreferencesError.locked) { try client.saveLogFilter(Self.filter("b"), replacingSameName: false) }
    #expect(throws: PreferencesError.locked) { try client.saveLogFilter(Self.filter("a"), replacingSameName: true) }
    #expect(throws: PreferencesError.locked) { try client.removeLogFilter(named: "a") }
    #expect(store.logFiltersSetCount == 0)
    #expect(store.logFilterItems == [Self.original("a")])
  }

  @Test("삭제는 같은 이름을 모두 지우고, 없으면 쓰지 않고 그대로 돌려준다")
  func remove() throws {
    let (client, store) = Self.fixture([Self.original("Errors"), Self.original("b"), Self.original("errors")])

    #expect(try client.removeLogFilter(named: "missing") == SavedLogFilterSetting(
      filters: [Self.filter("Errors"), Self.filter("b")],
      isLocked: false
    ))
    #expect(store.logFiltersSetCount == 0)

    let setting = try client.removeLogFilter(named: "ERRORS")

    #expect(setting == SavedLogFilterSetting(filters: [Self.filter("b")], isLocked: false))
    #expect(store.logFilterItems == [Self.original("b")])
    #expect(store.logFiltersSetCount == 1)
  }

  @Test("동시에 서로 다른 이름을 저장해도 둘 다 남는다 (5개 × 10번)")
  func concurrentSaves() async {
    let (client, store) = Self.fixture()

    await withTaskGroup(of: Void.self) { group in
      for task in 0 ..< 5 {
        group.addTask {
          for index in 0 ..< 10 {
            _ = try? client.saveLogFilter(Self.filter("t\(task)-\(index)"), replacingSameName: false)
          }
        }
      }
    }

    let names = client.savedLogFilters().filters.map(\.name)
    #expect(names.count == 50)
    #expect(Set(names).count == 50)
    #expect(store.logFiltersSetCount == 50)
  }
}
