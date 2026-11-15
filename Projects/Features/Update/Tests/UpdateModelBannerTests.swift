import Core
import Foundation
import PreferencesInterface
import PreferencesTesting
import Testing
import UpdateCheckInterface
import UpdateCheckTesting
@testable import UpdateFeature

/// 배너 닫기(× = 그 버전을 24시간 숨김)와 "이 버전 건너뛰기".
@MainActor
struct UpdateModelBannerTests: UpdateModelTesting {
  /// 새 버전 1.3.0 배너가 보이는 Model.
  static func shownModel(
    updateCheck: UpdateCheckClientFake = UpdateCheckClientFake(result: .success(v130)),
    preferences: PreferencesClientFake = PreferencesClientFake(),
    clock: TestClock = TestClock()
  ) async -> UpdateModel {
    let model = Self.makeModel(updateCheck: updateCheck, preferences: preferences, clock: clock)
    await model.appLaunched()
    #expect(model.availableUpdate == v130)
    return model
  }

  // MARK: - 닫기(숨김)

  @Test("닫기는 {1.3.0, 지금} 을 저장하고 배너를 뺀다")
  func dismissSaves() async {
    let preferences = PreferencesClientFake()
    let clock = TestClock()
    let model = await Self.shownModel(preferences: preferences, clock: clock)

    model.bannerDismissed()

    #expect(preferences.storedUpdateBannerDismissal == UpdateBannerDismissal(version: v130, dismissedAt: clock.now))
    #expect(model.availableUpdate == nil)
  }

  @Test("숨긴 버전을 24시간 안에 다시 내는 자동·수동 결과에는 배너가 없고, 수동 창은 건너뛰지 않은 새 버전을 보인다")
  func dismissedSameVersion() async {
    let clock = TestClock()
    let model = await Self.shownModel(clock: clock)
    model.bannerDismissed()

    clock.advance(by: 23 * .hour)
    await model.checkForUpdatesRequested()

    #expect(model.availableUpdate == nil)
    #expect(model.manualCheck == .finished(.newer(v130, current: v120, skipped: false)))
  }

  @Test("숨긴 뒤 더 새 버전이 나오면 배너가 바로 보인다")
  func newerAfterDismiss() async {
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    let model = await Self.shownModel(updateCheck: updateCheck)
    model.bannerDismissed()

    updateCheck.setResult(.success(v140))
    await model.checkForUpdatesRequested()

    #expect(model.availableUpdate == v140)
  }

  @Test("숨긴 지 24시간 뒤 활성화하면(기록 기한 전) 요청 없이 이 실행의 마지막 결과로 배너가 다시 보인다")
  func dismissalExpiresOnActivation() async {
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    let clock = TestClock()
    let model = await Self.shownModel(updateCheck: updateCheck, clock: clock)
    model.bannerDismissed()
    // 숨긴 뒤의 수동 확인이 기록을 늦춰, 숨김이 끝나는 때에는 기록 기한 전이다.
    clock.advance(by: 23 * .hour)
    await model.checkForUpdatesRequested()
    model.checkWindowClosed()
    #expect(model.availableUpdate == nil)

    clock.advance(by: .hour)
    await model.appBecameActive()

    #expect(updateCheck.callCount == 2)
    #expect(model.availableUpdate == v130)
  }

  @Test("저장된 숨김의 시각이 미래면(시계가 뒤로 감) 숨기지 않는다")
  func futureDismissalIgnored() async {
    let preferences = PreferencesClientFake()
    let clock = TestClock()
    preferences.setStoredUpdateBannerDismissal(
      UpdateBannerDismissal(version: v130, dismissedAt: clock.now.addingTimeInterval(.hour)),
      isLocked: false
    )

    let model = Self.makeModel(preferences: preferences, clock: clock)
    await model.appLaunched()

    #expect(model.availableUpdate == v130)
  }

  @Test("숨김 키가 잠겨 저장하지 못해도 이 실행 동안은 숨긴다")
  func lockedDismissalKeptInSession() async {
    let preferences = PreferencesClientFake()
    preferences.setStoredUpdateBannerDismissal(nil, isLocked: true)
    let clock = TestClock()
    let model = await Self.shownModel(preferences: preferences, clock: clock)

    model.bannerDismissed()
    clock.advance(by: .hour)
    await model.checkForUpdatesRequested()

    #expect(preferences.storedUpdateBannerDismissal == nil)
    #expect(model.availableUpdate == nil)
  }

  @Test("배너가 없을 때 닫기는 아무것도 저장하지 않는다")
  func dismissWithoutBanner() {
    let preferences = PreferencesClientFake()
    let model = Self.makeModel(preferences: preferences)

    model.bannerDismissed()

    #expect(Self.writeCount(preferences) == 0)
  }

  // MARK: - 건너뛰기

  @Test("건너뛰기는 1.3.0 을 저장하고 배너를 빼며, 창이 그 버전을 보이고 있으면 건너뛴 버전으로 바꾼다")
  func skipSaves() async {
    let preferences = PreferencesClientFake()
    let model = Self.makeModel(preferences: preferences)
    await model.checkForUpdatesRequested()

    model.skipVersionTapped(v130)

    #expect(preferences.storedSkippedUpdateVersion == "1.3.0")
    #expect(model.availableUpdate == nil)
    #expect(model.manualCheck == .finished(.newer(v130, current: v120, skipped: true)))
  }

  @Test("건너뛰기 키가 잠겨 저장하지 못해도 이 실행 동안은 배너에서 뺀다")
  func lockedSkipKeptInSession() async {
    let preferences = PreferencesClientFake()
    preferences.setStoredSkippedUpdateVersion(nil, isLocked: true)
    let clock = TestClock()
    let model = await Self.shownModel(preferences: preferences, clock: clock)

    model.skipVersionTapped(v130)
    clock.advance(by: .day)
    await model.appBecameActive()

    #expect(preferences.storedSkippedUpdateVersion == nil)
    #expect(model.availableUpdate == nil)
  }

  @Test("건너뛴 버전은 숨김이 끝나도 배너에 없다 (건너뛰기가 숨김보다 먼저다)")
  func skipWinsOverDismissal() async {
    let clock = TestClock()
    let model = await Self.shownModel(clock: clock)
    model.bannerDismissed()
    model.skipVersionTapped(v130)

    clock.advance(by: 2 * .day)
    await model.appBecameActive()

    #expect(model.availableUpdate == nil)
  }

  @Test("건너뛴 뒤 더 높은 버전이 나오면 배너가 보인다")
  func newerAfterSkip() async {
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    let model = await Self.shownModel(updateCheck: updateCheck)
    model.skipVersionTapped(v130)

    updateCheck.setResult(.success(v140))
    await model.checkForUpdatesRequested()

    #expect(model.availableUpdate == v140)
  }

  // MARK: - 결과에 따른 배너

  @Test("최신 결과가 오면 전 배너가 사라진다")
  func upToDateClearsBanner() async {
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    let model = await Self.shownModel(updateCheck: updateCheck)

    updateCheck.setResult(.success(v120))
    await model.checkForUpdatesRequested()

    #expect(model.availableUpdate == nil)
    #expect(model.manualCheck == .finished(.upToDate(current: v120)))
  }

  @Test("실패 결과는 전 배너를 그대로 둔다")
  func failureKeepsBanner() async {
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    let model = await Self.shownModel(updateCheck: updateCheck)

    updateCheck.setResult(.failure(.refused))
    await model.checkForUpdatesRequested()

    #expect(model.availableUpdate == v130)
  }
}
