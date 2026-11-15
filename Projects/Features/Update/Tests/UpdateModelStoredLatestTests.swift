import Core
import Foundation
import PreferencesInterface
import PreferencesTesting
import Testing
import UpdateCheckInterface
import UpdateCheckTesting
@testable import UpdateFeature

/// 서버가 답한 최신 버전의 저장(`LatestKnownUpdateVersion`)과, 이 실행에 결과가 없을 때 그 저장값으로 정하는 배너.
/// 같은 Fake 를 두 Model 이 나눠 써 "다시 켬" 을 흉내 낸다. 지금 버전은 1.2.0.
@MainActor
struct UpdateModelStoredLatestTests: UpdateModelTesting {
  /// 저장값과 마지막 확인 기록(1시간 전, 자동 확인 기한 전)을 넣은 Preferences.
  static func storedPreferences(_ latest: String?, clock: TestClock) -> PreferencesClientFake {
    let preferences = PreferencesClientFake()
    preferences.setStoredLatestKnownUpdateVersion(latest, isLocked: false)
    preferences.setStoredLastUpdateCheck(clock.now.addingTimeInterval(-.hour), isLocked: false)
    return preferences
  }

  static func dismissal(_ raw: String, at date: Date) throws -> UpdateBannerDismissal {
    try UpdateBannerDismissal(version: #require(AppVersion(raw)), dismissedAt: date)
  }

  // MARK: - 저장

  @Test("성공 응답의 최신 버전을 정규화해 저장한다 (새 버전·최신·지금보다 낮음 모두)", arguments: [
    "1.3.0", "1.2.0", "1.1.0", "v1.3",
  ])
  func savesLatest(raw: String) async throws {
    let version = try #require(AppVersion(raw))
    let preferences = PreferencesClientFake()
    let model = Self.makeModel(updateCheck: UpdateCheckClientFake(result: .success(version)), preferences: preferences)

    await model.appLaunched()

    #expect(Self.recordedLatest(preferences) == [version.description])
    #expect(preferences.storedLatestKnownUpdateVersion == version.description)
  }

  @Test("v1.3 은 1.3.0 으로 저장한다")
  func savesNormalized() async throws {
    let preferences = PreferencesClientFake()
    let version = try #require(AppVersion("v1.3"))
    let model = Self.makeModel(updateCheck: UpdateCheckClientFake(result: .success(version)), preferences: preferences)

    await model.appLaunched()

    #expect(preferences.storedLatestKnownUpdateVersion == "1.3.0")
  }

  @Test("숫자 버전이 아닌 답이면 저장값을 지운다")
  func clearsOnUnrecognized() async {
    let clock = TestClock()
    let preferences = PreferencesClientFake()
    preferences.setStoredLatestKnownUpdateVersion("1.3.0", isLocked: false)
    let model = Self.makeModel(
      updateCheck: UpdateCheckClientFake(result: .success(nil)),
      preferences: preferences,
      clock: clock
    )

    await model.appLaunched()

    #expect(Self.recordedLatest(preferences) == [nil])
    #expect(preferences.storedLatestKnownUpdateVersion == nil)
    #expect(model.availableUpdate == nil)
  }

  @Test("지금 버전을 몰라도 저장하고, 배너는 없다")
  func savesWithoutCurrentVersion() async {
    let preferences = PreferencesClientFake()
    let model = Self.makeModel(preferences: preferences, currentVersion: nil)

    await model.appLaunched()

    #expect(preferences.storedLatestKnownUpdateVersion == "1.3.0")
    #expect(model.availableUpdate == nil)
  }

  @Test("실패는 저장값을 쓰지도 지우지도 않는다", arguments: [
    UpdateCheckError.offline, .timedOut, .refused, .notFound, .httpStatus(500), .unexpectedResponse,
  ])
  func failureKeepsStored(error: UpdateCheckError) async {
    let preferences = PreferencesClientFake()
    preferences.setStoredLatestKnownUpdateVersion("1.1.0", isLocked: false)
    let model = Self.makeModel(updateCheck: UpdateCheckClientFake(result: .failure(error)), preferences: preferences)

    await model.appLaunched()
    await model.checkForUpdatesRequested()

    #expect(Self.recordedLatest(preferences).isEmpty)
    #expect(preferences.storedLatestKnownUpdateVersion == "1.1.0")
  }

  @Test("수동 확인의 성공 결과도 저장한다")
  func manualSaves() async {
    let clock = TestClock()
    let preferences = Self.storedPreferences(nil, clock: clock)
    let model = Self.makeModel(preferences: preferences, clock: clock)

    await model.checkForUpdatesRequested()

    #expect(Self.recordedLatest(preferences) == ["1.3.0"])
  }

  // MARK: - 다시 켬

  @Test("회귀: 배너를 띄운 뒤 다시 켜면 요청 없이 저장값으로 배너가 보인다")
  func relaunchKeepsBanner() async {
    let clock = TestClock()
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    let preferences = PreferencesClientFake()
    let first = Self.makeModel(updateCheck: updateCheck, preferences: preferences, clock: clock)
    await first.appLaunched()
    #expect(first.availableUpdate == v130)
    let recorded = preferences.storedLastUpdateCheck

    clock.advance(by: .hour)
    let second = Self.makeModel(updateCheck: updateCheck, preferences: preferences, clock: clock)
    await second.appLaunched()

    #expect(second.availableUpdate == v130)
    #expect(updateCheck.callCount == 1)
    #expect(preferences.storedLastUpdateCheck == recorded)
  }

  @Test("켤 때·활성화 때 저장값 1.3.0 이면 요청 없이 배너가 보인다", arguments: AutomaticEvent.allCases)
  func storedBannerOnEvent(event: AutomaticEvent) async {
    let clock = TestClock()
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    let model = Self.makeModel(
      updateCheck: updateCheck,
      preferences: Self.storedPreferences("1.3.0", clock: clock),
      clock: clock
    )

    await event.send(to: model)

    #expect(model.availableUpdate == v130)
    #expect(updateCheck.callCount == 0)
  }

  @Test("저장값이 지금 버전 이하이거나 해석할 수 없으면 배너가 없다", arguments: ["1.2.0", "1.1.0", "abc", ""])
  func storedNotNewer(raw: String) async {
    let clock = TestClock()
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    let model = Self.makeModel(
      updateCheck: updateCheck,
      preferences: Self.storedPreferences(raw, clock: clock),
      clock: clock
    )

    await model.appLaunched()

    #expect(model.availableUpdate == nil)
    #expect(updateCheck.callCount == 0)
  }

  @Test("지금 버전을 모르면 저장값이 있어도 배너가 없다")
  func storedWithoutCurrentVersion() async {
    let clock = TestClock()
    let model = Self.makeModel(
      preferences: Self.storedPreferences("1.3.0", clock: clock),
      currentVersion: nil,
      clock: clock
    )

    await model.appLaunched()

    #expect(model.availableUpdate == nil)
  }

  // MARK: - 건너뛰기·숨김

  @Test("건너뛴 버전은 저장값이어도 배너가 없다")
  func storedSkipped() async {
    let clock = TestClock()
    let preferences = Self.storedPreferences("1.3.0", clock: clock)
    preferences.setStoredSkippedUpdateVersion("1.3.0", isLocked: false)
    let model = Self.makeModel(preferences: preferences, clock: clock)

    await model.appLaunched()

    #expect(model.availableUpdate == nil)
  }

  @Test("같은 버전을 1시간 전에 숨겼으면 저장값 배너가 없다")
  func storedDismissedRecently() async throws {
    let clock = TestClock()
    let preferences = Self.storedPreferences("1.3.0", clock: clock)
    try preferences.setStoredUpdateBannerDismissal(
      Self.dismissal("1.3.0", at: clock.now.addingTimeInterval(-.hour)),
      isLocked: false
    )
    let model = Self.makeModel(preferences: preferences, clock: clock)

    await model.appLaunched()

    #expect(model.availableUpdate == nil)
  }

  @Test("숨김이 25시간 전이면 저장값 배너가 보인다")
  func storedDismissalExpired() async throws {
    let clock = TestClock()
    let preferences = Self.storedPreferences("1.3.0", clock: clock)
    try preferences.setStoredUpdateBannerDismissal(
      Self.dismissal("1.3.0", at: clock.now.addingTimeInterval(-25 * .hour)),
      isLocked: false
    )
    let model = Self.makeModel(preferences: preferences, clock: clock)

    await model.appLaunched()

    #expect(model.availableUpdate == v130)
  }

  @Test("다른 버전(1.2.5)의 숨김은 저장값 1.3.0 배너를 가리지 않는다")
  func storedDismissalOtherVersion() async throws {
    let clock = TestClock()
    let preferences = Self.storedPreferences("1.3.0", clock: clock)
    try preferences.setStoredUpdateBannerDismissal(
      Self.dismissal("1.2.5", at: clock.now.addingTimeInterval(-.hour)),
      isLocked: false
    )
    let model = Self.makeModel(preferences: preferences, clock: clock)

    await model.appLaunched()

    #expect(model.availableUpdate == v130)
  }

  @Test("저장값 배너를 닫으면 다시 켜도 없고, 24시간 뒤 활성화 때 요청 없이 다시 보인다")
  func dismissStoredBanner() async {
    let clock = TestClock()
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    let preferences = Self.storedPreferences("1.3.0", clock: clock)
    let first = Self.makeModel(updateCheck: updateCheck, preferences: preferences, clock: clock)
    await first.appLaunched()
    #expect(first.availableUpdate == v130)

    first.bannerDismissed()
    #expect(preferences.storedUpdateBannerDismissal == UpdateBannerDismissal(version: v130, dismissedAt: clock.now))
    #expect(first.availableUpdate == nil)

    let second = Self.makeModel(updateCheck: updateCheck, preferences: preferences, clock: clock)
    await second.appLaunched()
    #expect(second.availableUpdate == nil)

    clock.advance(by: .day)
    preferences.setStoredLastUpdateCheck(clock.now, isLocked: false)
    await second.appBecameActive()

    #expect(second.availableUpdate == v130)
    #expect(updateCheck.callCount == 0)
  }

  // MARK: - 자동 확인 끔

  @Test("자동 확인을 끄면(잠김 여부 무관) 저장값 배너가 없고, 이 실행의 수동 확인 결과는 보인다", arguments: [false, true])
  func automaticOff(isLocked: Bool) async {
    let clock = TestClock()
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    let preferences = Self.storedPreferences("1.3.0", clock: clock)
    preferences.setStoredAutomaticUpdateCheck(false, isLocked: isLocked)
    let model = Self.makeModel(updateCheck: updateCheck, preferences: preferences, clock: clock)

    await model.appLaunched()
    #expect(model.availableUpdate == nil)
    #expect(updateCheck.callCount == 0)

    await model.checkForUpdatesRequested()

    #expect(model.availableUpdate == v130)
    #expect(Self.recordedLatest(preferences) == ["1.3.0"])
  }

  // MARK: - 이 실행의 결과가 먼저

  @Test("저장값 배너 뒤 자동 확인 결과가 배너와 저장값을 정한다 (실패면 그대로)", arguments: SessionCase.allCases)
  func sessionResultWins(sessionCase: SessionCase) async {
    let clock = TestClock()
    let updateCheck = UpdateCheckClientFake(result: sessionCase.result)
    let preferences = PreferencesClientFake()
    preferences.setStoredLatestKnownUpdateVersion("1.3.0", isLocked: false)
    let model = Self.makeModel(updateCheck: updateCheck, preferences: preferences, clock: clock)

    await model.appLaunched()

    #expect(updateCheck.callCount == 1)
    #expect(model.availableUpdate == sessionCase.banner)
    #expect(preferences.storedLatestKnownUpdateVersion == sessionCase.stored)
  }

  @Test("키가 잠겼으면 켤 때 잠긴 값으로 보이고, 이 실행의 결과는 메모리로 배너를 정하며 저장값을 다시 읽지 않는다")
  func lockedKey() async {
    let clock = TestClock()
    let updateCheck = UpdateCheckClientFake(result: .success(v140))
    let preferences = Self.storedPreferences(nil, clock: clock)
    preferences.setStoredLatestKnownUpdateVersion("1.3.0", isLocked: true)
    let model = Self.makeModel(updateCheck: updateCheck, preferences: preferences, clock: clock)

    await model.appLaunched()
    #expect(model.availableUpdate == v130)
    #expect(updateCheck.callCount == 0)

    await model.checkForUpdatesRequested()
    #expect(model.availableUpdate == v140)
    #expect(preferences.storedLatestKnownUpdateVersion == "1.3.0")

    model.checkWindowClosed()
    updateCheck.setResult(.success(v120))
    await model.checkForUpdatesRequested()

    #expect(model.availableUpdate == nil)
    #expect(preferences.storedLatestKnownUpdateVersion == "1.3.0")
  }
}

/// 저장값 1.3.0 배너가 보이는 실행에서 자동 확인이 낸 결과와, 그 뒤의 배너·저장값.
enum SessionCase: CaseIterable, Sendable, CustomTestStringConvertible {
  case offline
  case upToDate
  case newer
  case unrecognized

  var result: Result<AppVersion?, UpdateCheckError> {
    switch self {
    case .offline: .failure(.offline)
    case .upToDate: .success(v120)
    case .newer: .success(v140)
    case .unrecognized: .success(nil)
    }
  }

  var banner: AppVersion? {
    switch self {
    case .offline: v130
    case .upToDate: nil
    case .newer: v140
    case .unrecognized: nil
    }
  }

  var stored: String? {
    switch self {
    case .offline: "1.3.0"
    case .upToDate: "1.2.0"
    case .newer: "1.4.0"
    case .unrecognized: nil
    }
  }

  var testDescription: String {
    switch self {
    case .offline: "오프라인 → 1.3.0 그대로"
    case .upToDate: "1.2.0 → 배너 없음"
    case .newer: "1.4.0 → 1.4.0"
    case .unrecognized: "숫자 버전 아님 → 배너 없음·지움"
    }
  }
}
