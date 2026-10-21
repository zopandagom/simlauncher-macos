import Core
import PreferencesInterface
import Testing
@testable import PreferencesImpl

struct PreferencesClientImplTests {
  static let first = "https://example.com/catalog.json"
  static let second = "https://other.example/catalog.json"

  static func url(_ raw: String) throws -> DownloadURL {
    try #require(DownloadURL(raw))
  }

  @Test("빈 저장소는 빈 목록, 잠기지 않음")
  func emptyStore() {
    let client = PreferencesClientImpl(store: InMemoryPreferenceStore())
    #expect(client.catalogURLs() == .empty)
  }

  @Test("저장된 목록과 강제 여부를 그대로 읽는다 (형식 검사 없음)")
  func readsStored() {
    let raws = [Self.first, "http://example.com/c.json", ""]
    let client = PreferencesClientImpl(store: InMemoryPreferenceStore(urls: raws, isForced: true))
    #expect(client.catalogURLs() == CatalogURLSetting(urls: raws, isLocked: true))
  }

  // MARK: - 추가

  @Test("추가하면 저장 문자열(앞뒤 공백 없이 인코딩된 값)을 끝에 붙여 저장하고 저장 뒤 목록을 돌려준다")
  func addAppends() throws {
    let store = InMemoryPreferenceStore(urls: [Self.first])
    let client = PreferencesClientImpl(store: store)
    let url = try Self.url("  https://other.example/빌드 카탈로그.json ")

    let setting = try client.addCatalogURL(url)

    let stored = "https://other.example/%EB%B9%8C%EB%93%9C%20%EC%B9%B4%ED%83%88%EB%A1%9C%EA%B7%B8.json"
    #expect(setting == CatalogURLSetting(urls: [Self.first, stored], isLocked: false))
    #expect(store.urls == [Self.first, stored])
    #expect(store.setCount == 1)
  }

  @Test(
    "같은 카탈로그(대소문자·:443·조각이 다른 표기)가 있으면 duplicate, 저장하지 않는다",
    arguments: [
      "https://example.com/catalog.json",
      "HTTPS://EXAMPLE.COM/catalog.json",
      "https://example.com:443/catalog.json",
      "https://example.com/catalog.json#top",
    ]
  )
  func addDuplicate(raw: String) throws {
    let store = InMemoryPreferenceStore(urls: ["http://x.example/c.json", Self.first])
    let client = PreferencesClientImpl(store: store)

    #expect(throws: PreferencesError.duplicate) { try client.addCatalogURL(Self.url(raw)) }
    #expect(store.setCount == 0)
    #expect(store.urls == ["http://x.example/c.json", Self.first])
  }

  @Test("잠겼으면 locked, 저장하지 않는다")
  func addLocked() throws {
    let store = InMemoryPreferenceStore(urls: [Self.first], isForced: true)
    let client = PreferencesClientImpl(store: store)

    #expect(throws: PreferencesError.locked) { try client.addCatalogURL(Self.url(Self.second)) }
    #expect(store.setCount == 0)
  }

  @Test("추가는 저장소를 다시 읽어 바깥에서 바뀐 값 위에 붙인다")
  func addReadsLatest() throws {
    let store = InMemoryPreferenceStore(urls: [Self.first])
    let client = PreferencesClientImpl(store: store)
    _ = client.catalogURLs()
    store.replace(urls: ["https://outside.example/c.json"], isForced: false)

    let setting = try client.addCatalogURL(Self.url(Self.second))

    #expect(setting.urls == ["https://outside.example/c.json", Self.second])
    #expect(store.urls == ["https://outside.example/c.json", Self.second])
  }

  @Test("추가 직전 바깥에서 잠기면 locked, 같은 카탈로그가 들어오면 duplicate")
  func addSeesOutsideLockAndDuplicate() throws {
    let store = InMemoryPreferenceStore(urls: [Self.first])
    let client = PreferencesClientImpl(store: store)

    store.replace(urls: [Self.first, Self.second], isForced: false)
    #expect(throws: PreferencesError.duplicate) { try client.addCatalogURL(Self.url(Self.second)) }
    store.replace(urls: [Self.first], isForced: true)
    #expect(throws: PreferencesError.locked) { try client.addCatalogURL(Self.url(Self.second)) }
    #expect(store.setCount == 0)
  }

  @Test("여러 Task 가 동시에 추가해도 쓰기를 잃지 않는다 (8개 × 50번)")
  func concurrentAdds() async throws {
    let store = InMemoryPreferenceStore()
    let client = PreferencesClientImpl(store: store)
    let urls = try (0 ..< 8).map { task in
      try (0 ..< 50).map { index in try Self.url("https://t\(task).example/\(index).json") }
    }

    await withTaskGroup(of: Void.self) { group in
      for batch in urls {
        group.addTask {
          for url in batch {
            _ = try? client.addCatalogURL(url)
          }
        }
      }
    }

    #expect(store.urls.count == 400)
    #expect(Set(store.urls).count == 400)
  }

  // MARK: - 삭제

  @Test("삭제는 같은 문자열을 모두 빼고 저장한 뒤 목록을 돌려준다")
  func removeAll() throws {
    let store = InMemoryPreferenceStore(urls: [Self.first, Self.second, Self.first, "HTTPS://EXAMPLE.COM/catalog.json"])
    let client = PreferencesClientImpl(store: store)

    let setting = try client.removeCatalogURL(Self.first)

    #expect(setting == CatalogURLSetting(urls: [Self.second, "HTTPS://EXAMPLE.COM/catalog.json"], isLocked: false))
    #expect(store.urls == setting.urls)
    #expect(store.setCount == 1)
  }

  @Test("없는 문자열이면 저장하지 않고 그대로 돌려준다")
  func removeMissing() throws {
    let store = InMemoryPreferenceStore(urls: [Self.first])
    let client = PreferencesClientImpl(store: store)

    #expect(try client.removeCatalogURL(Self.second) == CatalogURLSetting(urls: [Self.first], isLocked: false))
    #expect(store.setCount == 0)
  }

  @Test("빈 문자열 항목도 지울 수 있고, 마지막 항목을 지우면 빈 목록을 쓴다")
  func removeToEmpty() throws {
    let store = InMemoryPreferenceStore(urls: [""])
    let client = PreferencesClientImpl(store: store)

    #expect(try client.removeCatalogURL("") == .empty)
    #expect(store.urls.isEmpty)
    #expect(store.setCount == 1)
  }

  @Test("잠겼으면 locked, 저장하지 않는다")
  func removeLocked() {
    let store = InMemoryPreferenceStore(urls: [Self.first], isForced: true)
    let client = PreferencesClientImpl(store: store)

    #expect(throws: PreferencesError.locked) { try client.removeCatalogURL(Self.first) }
    #expect(store.setCount == 0)
    #expect(store.urls == [Self.first])
  }

  @Test("삭제는 저장소를 다시 읽어 바깥에서 더한 값을 지우지 않는다")
  func removeReadsLatest() throws {
    let store = InMemoryPreferenceStore(urls: [Self.first])
    let client = PreferencesClientImpl(store: store)
    _ = client.catalogURLs()
    store.replace(urls: [Self.first, Self.second], isForced: false)

    #expect(try client.removeCatalogURL(Self.first).urls == [Self.second])
  }
}
