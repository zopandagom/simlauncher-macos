import Core
import Foundation
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

struct PreferencesClientFakeAndroidTests {
  @Test("SDK 위치: 넣은 값을 읽고, 쓰기는 nil 이면 absent·문자열이면 path, 호출을 기록한다")
  func sdkPath() throws {
    let fake = PreferencesClientFake(androidSDKPath: AndroidSDKPathSetting(value: .path("/a"), isLocked: false))

    #expect(fake.androidSDKPath() == AndroidSDKPathSetting(value: .path("/a"), isLocked: false))
    try fake.setAndroidSDKPath("/b")
    #expect(fake.storedAndroidSDKPath.value == .path("/b"))
    try fake.setAndroidSDKPath(nil)
    #expect(fake.storedAndroidSDKPath == .absent)
    #expect(fake.calls == [.androidSDKPath, .setAndroidSDKPath("/b"), .setAndroidSDKPath(nil)])
  }

  @Test("SDK 위치가 잠겼으면 locked, 값은 그대로")
  func sdkPathLocked() {
    let locked = AndroidSDKPathSetting(value: .path("/a"), isLocked: true)
    let fake = PreferencesClientFake(androidSDKPath: locked)

    #expect(throws: PreferencesError.locked) { try fake.setAndroidSDKPath(nil) }
    #expect(fake.storedAndroidSDKPath == locked)
  }

  @Test("지문: 더하기는 합집합, 잠겼으면 locked 이고 그대로")
  func licenses() throws {
    let fake = PreferencesClientFake(androidSDKPath: .absent, androidLicenses: ["a"])

    try fake.addAcceptedAndroidLicenses(["b"])
    #expect(fake.acceptedAndroidLicenses() == ["a", "b"])

    fake.setStoredAndroidLicenses(["admin"], isLocked: true)
    #expect(throws: PreferencesError.locked) { try fake.addAcceptedAndroidLicenses(["c"]) }
    #expect(fake.storedAndroidLicenses == ["admin"])
    #expect(fake.calls == [
      .addAcceptedAndroidLicenses(["b"]),
      .acceptedAndroidLicenses,
      .addAcceptedAndroidLicenses(["c"]),
    ])
  }
}

struct PreferencesClientFakeLogFilterTests {
  static func filter(_ name: String, text: String = "x") -> SavedLogFilter {
    SavedLogFilter(
      name: name,
      conditions: [SavedLogFilter.Condition(kind: .contains, text: text, isExcluded: false)],
      isCaseSensitive: false
    )!
  }

  @Test("Fake 로그 필터 저장·덮어쓰기·삭제는 Impl 과 같은 판정이고 호출을 기록한다")
  func saveReplaceRemove() throws {
    let fake = PreferencesClientFake(logFilters: [Self.filter("Errors"), Self.filter("b")])

    #expect(fake.savedLogFilters() == SavedLogFilterSetting(
      filters: [Self.filter("Errors"), Self.filter("b")],
      isLocked: false
    ))
    #expect(throws: PreferencesError.duplicate) {
      try fake.saveLogFilter(Self.filter(" errors "), replacingSameName: false)
    }
    let replaced = try fake.saveLogFilter(Self.filter("errors", text: "new"), replacingSameName: true)
    #expect(replaced.filters == [Self.filter("errors", text: "new"), Self.filter("b")])
    let appended = try fake.saveLogFilter(Self.filter("c"), replacingSameName: false)
    #expect(appended.filters.map(\.name) == ["errors", "b", "c"])
    let removed = try fake.removeLogFilter(named: "B")
    #expect(removed.filters.map(\.name) == ["errors", "c"])
    #expect(try fake.removeLogFilter(named: "missing").filters.map(\.name) == ["errors", "c"])

    #expect(fake.calls == [
      .savedLogFilters,
      .saveLogFilter("errors", replacingSameName: false),
      .saveLogFilter("errors", replacingSameName: true),
      .saveLogFilter("c", replacingSameName: false),
      .removeLogFilter("B"),
      .removeLogFilter("missing"),
    ])
  }

  @Test("Fake 는 잠김이면 locked, 50개면 limitReached, 읽지 못한 항목(nil)을 보존한다")
  func lockedLimitAndUnreadable() throws {
    let fifty: [SavedLogFilter?] = (0 ..< 50).map { Self.filter("f\($0)") }
    let fake = PreferencesClientFake(logFilters: [nil] + fifty)

    #expect(throws: PreferencesError.limitReached) {
      try fake.saveLogFilter(Self.filter("new"), replacingSameName: false)
    }
    _ = try fake.saveLogFilter(Self.filter("F0", text: "new"), replacingSameName: true)
    #expect(fake.storedLogFilters.first == .some(nil))
    #expect(fake.storedLogFilters[1] == Self.filter("F0", text: "new"))

    fake.setStoredLogFilters([Self.filter("a"), nil], isLocked: true)
    #expect(fake.savedLogFilters() == SavedLogFilterSetting(filters: [Self.filter("a")], isLocked: true))
    #expect(throws: PreferencesError.locked) { try fake.saveLogFilter(Self.filter("b"), replacingSameName: false) }
    #expect(throws: PreferencesError.locked) { try fake.removeLogFilter(named: "a") }
    #expect(fake.storedLogFilters == [Self.filter("a"), nil])
    #expect(fake.storedLogFiltersLocked)

    fake.setStoredLogFilters([nil, Self.filter("a"), nil], isLocked: false)
    _ = try fake.removeLogFilter(named: "a")
    #expect(fake.storedLogFilters == [nil, nil])
  }

  @Test("샘플 필터는 규칙을 지키고 이름이 서로 다르다")
  func samples() {
    let samples: [SavedLogFilter] = [.sampleErrors, .sampleHTTP, .sampleInvalidRegex]
    #expect(SavedLogFilterList.visible(samples) == samples)
    #expect(SavedLogFilter.sampleHTTP.isCaseSensitive)
    #expect(SavedLogFilter.sampleInvalidRegex.conditions.first?.kind == .regex)
  }
}

// MARK: - 업데이트 알림

extension PreferencesClientFakeTests {
  static let updateDate = Date(timeIntervalSince1970: 1_800_000_000)

  static func dismissal(_ raw: String) throws -> UpdateBannerDismissal {
    try UpdateBannerDismissal(version: #require(AppVersion(raw)), dismissedAt: self.updateDate)
  }

  @Test("업데이트 값 기본: 자동 켬·잠김 없음, 나머지 nil")
  func updateDefaults() {
    let fake = PreferencesClientFake()
    #expect(fake.automaticUpdateCheck() == .enabledDefault)
    #expect(fake.skippedUpdateVersion() == nil)
    #expect(fake.lastUpdateCheck() == nil)
    #expect(fake.updateBannerDismissal() == nil)
    #expect(fake.calls == [.automaticUpdateCheck, .skippedUpdateVersion, .lastUpdateCheck, .updateBannerDismissal])
  }

  @Test("업데이트 값 쓰기·읽기와 호출 기록")
  func updateWrites() throws {
    let fake = PreferencesClientFake()
    let dismissal = try Self.dismissal("1.3.0")

    try fake.setAutomaticUpdateCheck(false)
    try fake.setSkippedUpdateVersion("1.3.0")
    fake.setLastUpdateCheck(Self.updateDate)
    try fake.setUpdateBannerDismissal(dismissal)

    #expect(fake.storedAutomaticUpdateCheck == AutomaticUpdateCheckSetting(isEnabled: false, isLocked: false))
    #expect(fake.storedSkippedUpdateVersion == "1.3.0")
    #expect(fake.storedLastUpdateCheck == Self.updateDate)
    #expect(fake.storedUpdateBannerDismissal == dismissal)
    #expect(fake.calls == [
      .setAutomaticUpdateCheck(false),
      .setSkippedUpdateVersion("1.3.0"),
      .setLastUpdateCheck(Self.updateDate),
      .setUpdateBannerDismissal(dismissal),
    ])
  }

  @Test("잠기면 set 이 locked 이고 쓰지 않으며, setLastUpdateCheck 는 조용히 무시한다")
  func updateLocked() throws {
    let fake = PreferencesClientFake()
    let old = try Self.dismissal("1.2.0")
    fake.setStoredAutomaticUpdateCheck(false, isLocked: true)
    fake.setStoredSkippedUpdateVersion("1.2.0", isLocked: true)
    fake.setStoredLastUpdateCheck(nil, isLocked: true)
    fake.setStoredUpdateBannerDismissal(old, isLocked: true)

    #expect(fake.automaticUpdateCheck() == AutomaticUpdateCheckSetting(isEnabled: false, isLocked: true))
    #expect(throws: PreferencesError.locked) { try fake.setAutomaticUpdateCheck(true) }
    #expect(throws: PreferencesError.locked) { try fake.setSkippedUpdateVersion("1.3.0") }
    fake.setLastUpdateCheck(Self.updateDate)
    #expect(throws: PreferencesError.locked) { try fake.setUpdateBannerDismissal(Self.dismissal("1.3.0")) }

    #expect(fake.storedAutomaticUpdateCheck == AutomaticUpdateCheckSetting(isEnabled: false, isLocked: true))
    #expect(fake.storedSkippedUpdateVersion == "1.2.0")
    #expect(fake.storedLastUpdateCheck == nil)
    #expect(fake.storedUpdateBannerDismissal == old)
    #expect(fake.calls.contains(.setLastUpdateCheck(Self.updateDate)))
  }

  @Test("setStored… 와 stored… 는 기록하지 않는다")
  func updateStoredDoesNotRecord() throws {
    let fake = PreferencesClientFake()
    fake.setStoredAutomaticUpdateCheck(true, isLocked: false)
    fake.setStoredSkippedUpdateVersion("1.3.0", isLocked: false)
    fake.setStoredLastUpdateCheck(Self.updateDate, isLocked: false)
    try fake.setStoredUpdateBannerDismissal(Self.dismissal("1.3.0"), isLocked: false)
    _ = fake.storedAutomaticUpdateCheck
    _ = fake.storedSkippedUpdateVersion
    _ = fake.storedLastUpdateCheck
    _ = fake.storedUpdateBannerDismissal

    #expect(fake.calls.isEmpty)
    #expect(fake.skippedUpdateVersion() == "1.3.0")
    #expect(fake.lastUpdateCheck() == Self.updateDate)
  }

  @Test("받은 최신 버전: 기본 nil, 쓰기·지우기를 기록하고, 잠기면 조용히 무시한다")
  func serverLatestVersion() {
    let fake = PreferencesClientFake()
    #expect(fake.latestKnownUpdateVersion() == nil)

    fake.setLatestKnownUpdateVersion("1.3.0")
    #expect(fake.storedLatestKnownUpdateVersion == "1.3.0")
    fake.setLatestKnownUpdateVersion(nil)
    #expect(fake.storedLatestKnownUpdateVersion == nil)

    fake.setStoredLatestKnownUpdateVersion("1.2.0", isLocked: true)
    fake.setLatestKnownUpdateVersion("1.4.0")
    #expect(fake.storedLatestKnownUpdateVersion == "1.2.0")
    #expect(fake.calls == [
      .latestKnownUpdateVersion,
      .setLatestKnownUpdateVersion("1.3.0"),
      .setLatestKnownUpdateVersion(nil),
      .setLatestKnownUpdateVersion("1.4.0"),
    ])
  }

  @Test("setStoredLatestKnownUpdateVersion 과 storedLatestKnownUpdateVersion 은 기록하지 않는다")
  func serverLatestStoredDoesNotRecord() {
    let fake = PreferencesClientFake()
    fake.setStoredLatestKnownUpdateVersion("1.3.0", isLocked: false)
    _ = fake.storedLatestKnownUpdateVersion

    #expect(fake.calls.isEmpty)
    #expect(fake.latestKnownUpdateVersion() == "1.3.0")
  }
}
