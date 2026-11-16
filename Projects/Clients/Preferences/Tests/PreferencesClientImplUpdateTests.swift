import Core
import Foundation
import PreferencesInterface
import Testing
@testable import PreferencesImpl

/// 업데이트 알림 키 `AutomaticUpdateCheck`·`SkippedUpdateVersion`·`LastUpdateCheck`·`DismissedUpdateBanner`·
/// `LatestKnownUpdateVersion` 읽기·쓰기 (InMemory 저장소).
struct PreferencesClientImplUpdateTests {
  static let date = Date(timeIntervalSince1970: 1_800_000_000)

  static func dismissal(_ raw: String = "1.3.0") throws -> UpdateBannerDismissal {
    try UpdateBannerDismissal(version: #require(AppVersion(raw)), dismissedAt: self.date)
  }

  // MARK: - 자동 확인

  @Test("자동 확인: 키 없음 → 켬·잠기지 않음")
  func automaticDefault() {
    let client = PreferencesClientImpl(store: InMemoryPreferenceStore())
    #expect(client.automaticUpdateCheck() == .enabledDefault)
  }

  @Test("자동 확인 쓰기: 끄기·켜기 모두 Bool 로 쓰고 다시 읽힌다")
  func writesAutomatic() throws {
    let store = InMemoryPreferenceStore()
    let client = PreferencesClientImpl(store: store)

    try client.setAutomaticUpdateCheck(false)
    #expect(client.automaticUpdateCheck() == AutomaticUpdateCheckSetting(isEnabled: false, isLocked: false))
    #expect(store.storedAutomaticUpdateCheck == .bool(false))

    try client.setAutomaticUpdateCheck(true)
    #expect(client.automaticUpdateCheck() == .enabledDefault)
    #expect(store.storedAutomaticUpdateCheck == .bool(true))
    #expect(store.automaticUpdateCheckSetCount == 2)
  }

  @Test("자동 확인이 강제면 locked·쓰지 않음·잠김 표시")
  func lockedAutomatic() {
    let store = InMemoryPreferenceStore()
    store.replaceAutomaticUpdateCheck(.bool(false), isForced: true)
    let client = PreferencesClientImpl(store: store)

    #expect(client.automaticUpdateCheck() == AutomaticUpdateCheckSetting(isEnabled: false, isLocked: true))
    #expect(throws: PreferencesError.locked) { try client.setAutomaticUpdateCheck(true) }
    #expect(store.automaticUpdateCheckSetCount == 0)
    #expect(store.storedAutomaticUpdateCheck == .bool(false))
  }

  @Test("강제 값을 읽을 수 없으면 끔·잠김")
  func unreadableForcedAutomatic() {
    let store = InMemoryPreferenceStore()
    store.replaceAutomaticUpdateCheck(.string("maybe"), isForced: true)
    let client = PreferencesClientImpl(store: store)

    #expect(client.automaticUpdateCheck() == AutomaticUpdateCheckSetting(isEnabled: false, isLocked: true))
  }

  @Test("옛 형식 문자열 YES 는 켬으로 읽는다")
  func legacyStringAutomatic() {
    let store = InMemoryPreferenceStore()
    store.replaceAutomaticUpdateCheck(.string("NO"), isForced: false)
    let client = PreferencesClientImpl(store: store)
    #expect(client.automaticUpdateCheck() == AutomaticUpdateCheckSetting(isEnabled: false, isLocked: false))

    store.replaceAutomaticUpdateCheck(.string("YES"), isForced: false)
    #expect(client.automaticUpdateCheck() == .enabledDefault)
  }

  // MARK: - 건너뛴 버전

  @Test("건너뛴 버전: 키 없음 nil, 쓰기·읽기")
  func skippedVersion() throws {
    let store = InMemoryPreferenceStore()
    let client = PreferencesClientImpl(store: store)
    #expect(client.skippedUpdateVersion() == nil)

    try client.setSkippedUpdateVersion("1.3.0")
    #expect(client.skippedUpdateVersion() == "1.3.0")
    #expect(store.skippedUpdateVersionSetCount == 1)
  }

  @Test("건너뛴 버전이 강제면 locked·쓰지 않음")
  func lockedSkippedVersion() {
    let store = InMemoryPreferenceStore()
    store.replaceSkippedUpdateVersion("1.2.0", isForced: true)
    let client = PreferencesClientImpl(store: store)

    #expect(throws: PreferencesError.locked) { try client.setSkippedUpdateVersion("1.3.0") }
    #expect(store.skippedUpdateVersionSetCount == 0)
    #expect(client.skippedUpdateVersion() == "1.2.0")
  }

  // MARK: - 마지막 확인 시각

  @Test("마지막 확인 시각: 키 없음 nil, 쓰기·읽기")
  func lastCheck() {
    let store = InMemoryPreferenceStore()
    let client = PreferencesClientImpl(store: store)
    #expect(client.lastUpdateCheck() == nil)

    client.setLastUpdateCheck(Self.date)
    #expect(client.lastUpdateCheck() == Self.date)
    #expect(store.lastUpdateCheckSetCount == 1)
  }

  @Test("마지막 확인 시각이 강제면 던지지 않고 쓰지 않는다")
  func lockedLastCheck() {
    let store = InMemoryPreferenceStore()
    store.replaceLastUpdateCheck(nil, isForced: true)
    let client = PreferencesClientImpl(store: store)

    client.setLastUpdateCheck(Self.date)
    #expect(store.lastUpdateCheckSetCount == 0)
    #expect(client.lastUpdateCheck() == nil)
  }

  // MARK: - 배너 숨김

  @Test("배너 숨김: 키 없음 nil, 쓰기·읽기")
  func bannerDismissal() throws {
    let store = InMemoryPreferenceStore()
    let client = PreferencesClientImpl(store: store)
    #expect(client.updateBannerDismissal() == nil)

    try client.setUpdateBannerDismissal(Self.dismissal())
    #expect(try client.updateBannerDismissal() == Self.dismissal())
    #expect(store.updateBannerDismissalSetCount == 1)
  }

  @Test("배너 숨김이 강제면 locked·쓰지 않음")
  func lockedBannerDismissal() throws {
    let store = InMemoryPreferenceStore()
    try store.replaceUpdateBannerDismissal(Self.dismissal("1.2.0"), isForced: true)
    let client = PreferencesClientImpl(store: store)

    #expect(throws: PreferencesError.locked) { try client.setUpdateBannerDismissal(Self.dismissal()) }
    #expect(store.updateBannerDismissalSetCount == 0)
    #expect(try client.updateBannerDismissal() == Self.dismissal("1.2.0"))
  }

  // MARK: - 받은 최신 버전

  @Test("서버가 답한 최신 버전: 키 없음 nil, 쓰기·읽기")
  func storesServerLatest() {
    let store = InMemoryPreferenceStore()
    let client = PreferencesClientImpl(store: store)
    #expect(client.latestKnownUpdateVersion() == nil)

    client.setLatestKnownUpdateVersion("1.3.0")
    #expect(client.latestKnownUpdateVersion() == "1.3.0")
    #expect(store.latestKnownUpdateVersionSetCount == 1)
  }

  @Test("받은 최신 버전에 nil 쓰기는 키를 지운다")
  func clearsServerLatest() {
    let store = InMemoryPreferenceStore()
    store.replaceLatestKnownUpdateVersion("1.3.0", isForced: false)
    let client = PreferencesClientImpl(store: store)

    client.setLatestKnownUpdateVersion(nil)
    #expect(client.latestKnownUpdateVersion() == nil)
    #expect(store.latestKnownUpdateVersionSetCount == 1)
  }

  @Test("받은 최신 버전이 강제면 던지지 않고 쓰지도 지우지도 않는다")
  func lockedServerLatest() {
    let store = InMemoryPreferenceStore()
    store.replaceLatestKnownUpdateVersion("1.3.0", isForced: true)
    let client = PreferencesClientImpl(store: store)

    client.setLatestKnownUpdateVersion("1.4.0")
    client.setLatestKnownUpdateVersion(nil)
    #expect(client.latestKnownUpdateVersion() == "1.3.0")
    #expect(store.latestKnownUpdateVersionSetCount == 0)
  }
}
