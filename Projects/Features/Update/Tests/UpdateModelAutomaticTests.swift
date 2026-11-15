import Core
import Foundation
import PreferencesInterface
import PreferencesTesting
import Testing
import UpdateCheckInterface
import UpdateCheckTesting
@testable import UpdateFeature

/// 자동 확인(실행·활성화): 조건(설정·24시간 기록·1시간 재시도·진행 중), 겹침, 기록 규칙, 결과별 배너.
@MainActor
struct UpdateModelAutomaticTests: UpdateModelTesting {
  // MARK: - 요청하지 않는 조건

  @Test("배포 저장소가 없으면 요청하지 않는다", arguments: AutomaticEvent.allCases)
  func unavailable(event: AutomaticEvent) async {
    let updateCheck = UpdateCheckClientFake(releasePageURL: nil)
    let model = Self.makeModel(updateCheck: updateCheck)

    await event.send(to: model)

    #expect(updateCheck.callCount == 0)
  }

  @Test("자동 확인이 꺼져 있으면(잠김 포함) 요청하지 않는다", arguments: AutomaticEvent.allCases, [false, true])
  func disabled(event: AutomaticEvent, isLocked: Bool) async {
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    let preferences = PreferencesClientFake()
    preferences.setStoredAutomaticUpdateCheck(false, isLocked: isLocked)
    let model = Self.makeModel(updateCheck: updateCheck, preferences: preferences)

    await event.send(to: model)

    #expect(updateCheck.callCount == 0)
  }

  @Test("마지막 확인 기록에서 24시간이 지나지 않았으면 요청하지 않는다", arguments: AutomaticEvent.allCases)
  func notDue(event: AutomaticEvent) async {
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    let preferences = PreferencesClientFake()
    let clock = TestClock()
    preferences.setStoredLastUpdateCheck(clock.now.addingTimeInterval(-.hour), isLocked: false)
    let model = Self.makeModel(updateCheck: updateCheck, preferences: preferences, clock: clock)

    await event.send(to: model)

    #expect(updateCheck.callCount == 0)
  }

  // MARK: - 요청하는 조건

  @Test(
    "기록이 없거나 24시간 지났거나 미래면(시계가 뒤로 감) 한 번 요청한다",
    arguments: AutomaticEvent.allCases, [nil, -.day, .hour] as [TimeInterval?]
  )
  func due(event: AutomaticEvent, recordOffset: TimeInterval?) async {
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    let preferences = PreferencesClientFake()
    let clock = TestClock()
    preferences.setStoredLastUpdateCheck(recordOffset.map { clock.now.addingTimeInterval($0) }, isLocked: false)
    let model = Self.makeModel(updateCheck: updateCheck, preferences: preferences, clock: clock)

    await event.send(to: model)

    #expect(updateCheck.callCount == 1)
    #expect(Self.recordedChecks(preferences) == [clock.now])
  }

  @Test("실행과 활성화가 겹치면(첫 요청이 멈춘 동안) 요청은 하나이고 둘 다 그 결과로 끝난다")
  func launchAndActivateOverlap() async {
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    updateCheck.suspend()
    let model = Self.makeModel(updateCheck: updateCheck)
    let launched = await Self.startSuspended(updateCheck) { await model.appLaunched() }

    let activated = Self.start { await model.appBecameActive() }
    await Self.waitUntil { activated.isFinished }
    updateCheck.resume()
    await launched.value()

    #expect(updateCheck.callCount == 1)
    #expect(model.availableUpdate == v130)
  }

  @Test("기록된 성공 뒤 활성화는 23시간이면 요청하지 않고 24시간이면 요청한다")
  func afterRecordedSuccess() async {
    let updateCheck = UpdateCheckClientFake(result: .success(v120))
    let clock = TestClock()
    let model = Self.makeModel(updateCheck: updateCheck, clock: clock)
    await model.appLaunched()
    #expect(updateCheck.callCount == 1)

    clock.advance(by: 23 * .hour)
    await model.appBecameActive()
    #expect(updateCheck.callCount == 1)

    clock.advance(by: .hour)
    await model.appBecameActive()
    #expect(updateCheck.callCount == 2)
  }

  @Test("오프라인 실패 뒤 활성화는 59분이면 요청하지 않고 60분이면 요청한다 (기록하지 않는다)")
  func afterOfflineFailure() async {
    let updateCheck = UpdateCheckClientFake(result: .failure(.offline))
    let preferences = PreferencesClientFake()
    let clock = TestClock()
    let model = Self.makeModel(updateCheck: updateCheck, preferences: preferences, clock: clock)
    await model.appLaunched()
    #expect(updateCheck.callCount == 1)

    clock.advance(by: 59 * 60)
    await model.appBecameActive()
    #expect(updateCheck.callCount == 1)

    clock.advance(by: 60)
    await model.appBecameActive()
    #expect(updateCheck.callCount == 2)
    #expect(Self.recordedChecks(preferences).isEmpty)
  }

  @Test("마지막 요청 시작이 미래면(시계가 뒤로 감) 재시도 간격 안이어도 요청한다")
  func retryAfterClockMovedBack() async {
    let updateCheck = UpdateCheckClientFake(result: .failure(.offline))
    let clock = TestClock()
    let model = Self.makeModel(updateCheck: updateCheck, clock: clock)
    await model.appLaunched()

    clock.advance(by: -2 * .hour)
    await model.appBecameActive()

    #expect(updateCheck.callCount == 2)
  }

  @Test("수동 확인이 오프라인으로 실패하면 자동 확인도 1시간 기다린다 (30분 뒤 활성화는 요청하지 않는다)")
  func manualFailureDelaysAutomatic() async {
    let updateCheck = UpdateCheckClientFake(result: .failure(.offline))
    let clock = TestClock()
    let model = Self.makeModel(updateCheck: updateCheck, clock: clock)
    await model.checkForUpdatesRequested()
    model.checkWindowClosed()

    clock.advance(by: 30 * 60)
    await model.appBecameActive()

    #expect(updateCheck.callCount == 1)
  }

  @Test("LastUpdateCheck 가 잠겨 기록할 수 없으면 성공 뒤에도 1시간에 한 번까지만 자동 요청한다")
  func lockedRecord() async {
    let updateCheck = UpdateCheckClientFake(result: .success(v120))
    let preferences = PreferencesClientFake()
    preferences.setStoredLastUpdateCheck(nil, isLocked: true)
    let clock = TestClock()
    let model = Self.makeModel(updateCheck: updateCheck, preferences: preferences, clock: clock)
    await model.appLaunched()

    clock.advance(by: 59 * 60)
    await model.appBecameActive()
    #expect(updateCheck.callCount == 1)

    clock.advance(by: 60)
    await model.appBecameActive()
    #expect(updateCheck.callCount == 2)
    #expect(preferences.storedLastUpdateCheck == nil)
  }

  // MARK: - 결과

  @Test("새 버전이면 배너에 보이고, 창 상태는 nil 그대로다")
  func newerShowsBanner() async {
    let model = Self.makeModel(updateCheck: UpdateCheckClientFake(result: .success(v130)))

    await model.appLaunched()

    #expect(model.availableUpdate == v130)
    #expect(model.manualCheck == nil)
  }

  @Test(
    "건너뛴 버전·최신·지금 버전 모름·버전 값 해석 불가·실패면 배너가 없다",
    arguments: [
      NoBannerCase(result: .success(v130), skipped: "1.3.0", current: v120),
      NoBannerCase(result: .success(v120), skipped: nil, current: v120),
      NoBannerCase(result: .success(v130), skipped: nil, current: nil),
      NoBannerCase(result: .success(nil), skipped: nil, current: v120),
      NoBannerCase(result: .failure(.refused), skipped: nil, current: v120),
    ]
  )
  func noBanner(testCase: NoBannerCase) async {
    let (result, skipped, current) = (testCase.result, testCase.skipped, testCase.current)
    let preferences = PreferencesClientFake()
    preferences.setStoredSkippedUpdateVersion(skipped, isLocked: false)
    let model = Self.makeModel(
      updateCheck: UpdateCheckClientFake(result: result),
      preferences: preferences,
      currentVersion: current
    )

    await model.appLaunched()

    #expect(model.availableUpdate == nil)
    #expect(model.manualCheck == nil)
  }

  @Test(
    "성공과 서버가 답한 실패(거절·404·그 밖 HTTP·응답 이상)는 끝난 시각을 기록한다",
    arguments: [
      .success(v130), .success(nil), .failure(.refused), .failure(.notFound), .failure(.httpStatus(500)),
      .failure(.unexpectedResponse),
    ] as [Result<AppVersion?, UpdateCheckError>]
  )
  func recordsServerAnswer(result: Result<AppVersion?, UpdateCheckError>) async {
    let updateCheck = UpdateCheckClientFake(result: result)
    updateCheck.suspend()
    let preferences = PreferencesClientFake()
    let clock = TestClock()
    let model = Self.makeModel(updateCheck: updateCheck, preferences: preferences, clock: clock)
    let launched = await Self.startSuspended(updateCheck) { await model.appLaunched() }

    clock.advance(by: 30)
    updateCheck.resume()
    await launched.value()

    #expect(Self.recordedChecks(preferences) == [TestClock.start.addingTimeInterval(30)])
  }

  @Test(
    "서버에 닿지 못한 실패(오프라인·시간 초과·연결 실패·취소·그 밖)는 기록하지 않는다",
    arguments: [.offline, .timedOut, .connectionFailed, .cancelled, .failed] as [UpdateCheckError]
  )
  func doesNotRecordUnreached(error: UpdateCheckError) async {
    let preferences = PreferencesClientFake()
    let model = Self.makeModel(updateCheck: UpdateCheckClientFake(result: .failure(error)), preferences: preferences)

    await model.appLaunched()

    #expect(Self.recordedChecks(preferences).isEmpty)
  }
}

struct NoBannerCase {
  let result: Result<AppVersion?, UpdateCheckError>
  let skipped: String?
  let current: AppVersion?
}
