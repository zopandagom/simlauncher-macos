import Core
import Foundation
import PreferencesInterface
import PreferencesTesting
import Testing
import UpdateCheckInterface
import UpdateCheckTesting
@testable import UpdateFeature

/// 수동 확인(메뉴·창 열기·"다시 시도"): 창 상태와 결과, 겹침, 자동 조건을 보지 않음.
@MainActor
struct UpdateModelManualTests: UpdateModelTesting {
  @Test("확인 중에는 .checking 이고, 새 버전이면 지금 버전과 함께 .newer(건너뛰지 않음)로 끝난다")
  func newer() async {
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    updateCheck.suspend()
    let model = Self.makeModel(updateCheck: updateCheck)
    let check = await Self.startSuspended(updateCheck) { await model.checkForUpdatesRequested() }
    #expect(model.manualCheck == .checking)

    updateCheck.resume()
    await check.value()

    #expect(model.manualCheck == .finished(.newer(v130, current: v120, skipped: false)))
    #expect(model.availableUpdate == v130)
  }

  @Test("건너뛴 버전이면 창에는 건너뛴 버전으로 보이고 배너는 없다")
  func skipped() async {
    let preferences = PreferencesClientFake()
    preferences.setStoredSkippedUpdateVersion("1.3.0", isLocked: false)
    let model = Self.makeModel(preferences: preferences)

    await model.checkForUpdatesRequested()

    #expect(model.manualCheck == .finished(.newer(v130, current: v120, skipped: true)))
    #expect(model.availableUpdate == nil)
  }

  @Test("최신 버전이 같거나 지금이 더 높으면 최신임이다", arguments: [v120, AppVersion("1.1.0")!])
  func upToDate(latest: AppVersion) async {
    let model = Self.makeModel(updateCheck: UpdateCheckClientFake(result: .success(latest)))

    await model.checkForUpdatesRequested()

    #expect(model.manualCheck == .finished(.upToDate(current: v120)))
  }

  @Test("지금 버전을 읽지 못했으면 최신 버전과 관계없이 비교 불가(지금 버전 모름)다", arguments: [v130, nil] as [AppVersion?])
  func currentUnknown(latest: AppVersion?) async {
    let model = Self.makeModel(updateCheck: UpdateCheckClientFake(result: .success(latest)), currentVersion: nil)

    await model.checkForUpdatesRequested()

    #expect(model.manualCheck == .finished(.currentUnknown))
    #expect(model.availableUpdate == nil)
  }

  @Test("버전 값이 숫자 버전이 아니면 비교 불가(버전 값 모름)다")
  func latestUnrecognized() async {
    let model = Self.makeModel(updateCheck: UpdateCheckClientFake(result: .success(nil)))

    await model.checkForUpdatesRequested()

    #expect(model.manualCheck == .finished(.latestUnrecognized))
  }

  @Test(
    "실패하면 그 에러로 .failed 다",
    arguments: [
      .offline, .timedOut, .connectionFailed, .refused, .notFound, .httpStatus(502), .unexpectedResponse, .failed,
      .cancelled,
    ] as [UpdateCheckError]
  )
  func failed(error: UpdateCheckError) async {
    let model = Self.makeModel(updateCheck: UpdateCheckClientFake(result: .failure(error)))

    await model.checkForUpdatesRequested()

    #expect(model.manualCheck == .finished(.failed(error)))
  }

  @Test("확인 중 연타하면 요청은 하나이고 둘 다 같은 결과로 끝난다")
  func repeatedRequests() async {
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    updateCheck.suspend()
    let model = Self.makeModel(updateCheck: updateCheck)
    let first = await Self.startSuspended(updateCheck) { await model.checkForUpdatesRequested() }
    let second = Self.start { await model.checkForUpdatesRequested() }

    updateCheck.resume()
    await first.value()
    await second.value()

    #expect(updateCheck.callCount == 1)
    #expect(model.manualCheck == .finished(.newer(v130, current: v120, skipped: false)))
  }

  @Test("자동 확인이 진행 중일 때 수동 확인은 새로 요청하지 않고 그 결과를 창에 보인다")
  func joinsAutomaticCheck() async {
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    updateCheck.suspend()
    let model = Self.makeModel(updateCheck: updateCheck)
    let automatic = await Self.startSuspended(updateCheck) { await model.appLaunched() }
    let manual = Self.start { await model.checkForUpdatesRequested() }
    await Self.waitUntil { model.manualCheck == .checking }

    updateCheck.resume()
    await automatic.value()
    await manual.value()

    #expect(updateCheck.callCount == 1)
    #expect(model.manualCheck == .finished(.newer(v130, current: v120, skipped: false)))
  }

  @Test("끝난 뒤 다시 요청하면 새로 요청한다")
  func requestsAgainAfterFinish() async {
    let updateCheck = UpdateCheckClientFake(result: .failure(.offline))
    let model = Self.makeModel(updateCheck: updateCheck)
    await model.checkForUpdatesRequested()

    updateCheck.setResult(.success(v130))
    await model.checkForUpdatesRequested()

    #expect(updateCheck.callCount == 2)
    #expect(model.manualCheck == .finished(.newer(v130, current: v120, skipped: false)))
  }

  @Test("자동 확인이 꺼져 있고 기록 기한 전이어도 수동 확인은 요청한다")
  func ignoresAutomaticConditions() async {
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    let preferences = PreferencesClientFake()
    let clock = TestClock()
    preferences.setStoredAutomaticUpdateCheck(false, isLocked: true)
    preferences.setStoredLastUpdateCheck(clock.now, isLocked: false)
    let model = Self.makeModel(updateCheck: updateCheck, preferences: preferences, clock: clock)

    await model.checkForUpdatesRequested()

    #expect(updateCheck.callCount == 1)
    #expect(Self.recordedChecks(preferences) == [clock.now])
  }

  @Test("배포 저장소가 없으면 창 상태가 nil 이고 요청하지 않는다")
  func unavailable() async {
    let updateCheck = UpdateCheckClientFake(releasePageURL: nil)
    let model = Self.makeModel(updateCheck: updateCheck)

    await model.checkForUpdatesRequested()

    #expect(model.manualCheck == nil)
    #expect(updateCheck.callCount == 0)
  }
}
