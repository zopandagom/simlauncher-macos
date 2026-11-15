import Core
import Foundation
import PreferencesTesting
import Testing
import UpdateCheckInterface
import UpdateCheckTesting
@testable import UpdateFeature

/// 배포 저장소가 없는 빌드(포크): 어떤 이벤트에도 요청·기록·배너·창 상태가 없다.
@MainActor
struct UpdateModelUnavailableTests: UpdateModelTesting {
  @Test("저장소가 없으면 모든 이벤트에 요청 0, 창 상태·배너 nil, Preferences 쓰기 0")
  func everyEventDoesNothing() async {
    let updateCheck = UpdateCheckClientFake(releasePageURL: nil)
    let preferences = PreferencesClientFake()
    let clock = TestClock()
    let model = Self.makeModel(updateCheck: updateCheck, preferences: preferences, clock: clock)
    #expect(!model.isAvailable)
    #expect(model.releasePageURL == nil)

    await model.appLaunched()
    await model.appBecameActive()
    await model.checkForUpdatesRequested()
    model.skipVersionTapped(v130)
    model.bannerDismissed()
    model.checkWindowClosed()
    clock.advance(by: 2 * .day)
    await model.appBecameActive()

    #expect(updateCheck.callCount == 0)
    #expect(model.manualCheck == nil)
    #expect(model.availableUpdate == nil)
    #expect(Self.writeCount(preferences) == 0)
  }

  @Test("저장소가 없으면 저장된 최신 버전 9.9.9 가 있어도 배너가 없고, 그 키를 읽지도 쓰지도 않는다")
  func storedLatestIgnored() async {
    let updateCheck = UpdateCheckClientFake(releasePageURL: nil)
    let preferences = PreferencesClientFake()
    preferences.setStoredLatestKnownUpdateVersion("9.9.9", isLocked: false)
    let clock = TestClock()
    let model = Self.makeModel(updateCheck: updateCheck, preferences: preferences, clock: clock)

    await model.appLaunched()
    #expect(model.availableUpdate == nil)
    await model.appBecameActive()
    await model.checkForUpdatesRequested()
    model.skipVersionTapped(v130)
    model.bannerDismissed()
    model.checkWindowClosed()
    clock.advance(by: 2 * .day)
    await model.appBecameActive()

    #expect(model.availableUpdate == nil)
    #expect(!preferences.calls.contains(.latestKnownUpdateVersion))
    #expect(Self.recordedLatest(preferences).isEmpty)
    #expect(preferences.storedLatestKnownUpdateVersion == "9.9.9")
  }
}
