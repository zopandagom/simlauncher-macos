import Core
import PreferencesInterface
import PreferencesTesting
import Testing

struct PreferencesClientFakeTests {
  static let first = "https://example.com/catalog.json"
  static let second = "https://other.example/catalog.json"

  static func url(_ raw: String) throws -> DownloadURL {
    try #require(DownloadURL(raw))
  }

  @Test("넣은 값을 읽고, 호출을 순서대로 기록한다")
  func readsAndRecords() throws {
    let fake = PreferencesClientFake(urls: [Self.first])

    #expect(fake.catalogURLs() == CatalogURLSetting(urls: [Self.first], isLocked: false))
    _ = try fake.addCatalogURL(Self.url(Self.second))
    _ = try fake.removeCatalogURL(Self.first)

    #expect(fake.calls == [.catalogURLs, .addCatalogURL(Self.second), .removeCatalogURL(Self.first)])
    #expect(fake.stored == CatalogURLSetting(urls: [Self.second], isLocked: false))
  }

  @Test("추가는 저장 문자열을 끝에 붙인다")
  func addAppends() throws {
    let fake = PreferencesClientFake(urls: [Self.first])
    let url = try Self.url(" https://other.example/a b.json ")

    #expect(try fake.addCatalogURL(url).urls == [Self.first, "https://other.example/a%20b.json"])
  }

  @Test("같은 카탈로그가 있으면 duplicate, 잠겼으면 locked (잠금 먼저), 목록은 그대로")
  func addRejects() throws {
    let fake = PreferencesClientFake(urls: [Self.first])
    #expect(throws: PreferencesError.duplicate) { try fake.addCatalogURL(Self.url("HTTPS://EXAMPLE.COM/catalog.json")) }

    fake.setStored(urls: [Self.first], isLocked: true)
    #expect(throws: PreferencesError.locked) { try fake.addCatalogURL(Self.url(Self.first)) }
    #expect(fake.stored == CatalogURLSetting(urls: [Self.first], isLocked: true))
  }

  @Test("삭제는 같은 문자열을 모두 빼고, 잠겼으면 locked")
  func remove() throws {
    let fake = PreferencesClientFake(urls: [Self.first, Self.second, Self.first])
    #expect(try fake.removeCatalogURL(Self.first).urls == [Self.second])
    #expect(try fake.removeCatalogURL("없음").urls == [Self.second])

    fake.setStored(urls: [Self.second], isLocked: true)
    #expect(throws: PreferencesError.locked) { try fake.removeCatalogURL(Self.second) }
    #expect(fake.stored.urls == [Self.second])
  }

  @Test("setStored 는 바깥 변경을 흉내 내고, setStored·stored 는 기록하지 않는다")
  func setStored() {
    let fake = PreferencesClientFake()
    fake.setStored(urls: [Self.first], isLocked: true)

    #expect(fake.stored == CatalogURLSetting(urls: [Self.first], isLocked: true))
    #expect(fake.calls.isEmpty)
    #expect(fake.catalogURLs() == CatalogURLSetting(urls: [Self.first], isLocked: true))
  }

  @Test("샘플 값")
  func samples() {
    #expect(!CatalogURLSetting.sample.isLocked)
    #expect(CatalogURLSetting.sample.urls.allSatisfy { DownloadURL($0) != nil })
    #expect(CatalogURLSetting.locked.isLocked)
    let statuses = CatalogURLList.entries(CatalogURLSetting.withProblems.urls).map(\.status)
    #expect(statuses.contains(.duplicate(firstIndex: 0)))
    #expect(statuses.contains(.invalid(.notHTTPS)))
    #expect(statuses.contains(.invalid(.empty)))
  }
}
