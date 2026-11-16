import Core
import Foundation
import PreferencesTesting
import Testing
import UpdateCheckInterface
import UpdateCheckTesting
@testable import UpdateFeature

/// 업데이트 확인 창 닫기·다시 열기와, 창이 결과를 보이는 동안 자동 확인이 끝났을 때.
@MainActor
struct UpdateModelWindowTests: UpdateModelTesting {
  @Test("확인 중 창을 닫으면 결과가 와도 창 상태는 nil 이고, 요청은 취소되지 않고 배너는 반영된다")
  func closeWhileChecking() async {
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    updateCheck.suspend()
    let model = Self.makeModel(updateCheck: updateCheck)
    let check = await Self.startSuspended(updateCheck) { await model.checkForUpdatesRequested() }

    model.checkWindowClosed()
    #expect(model.manualCheck == nil)
    updateCheck.resume()
    await check.value()

    #expect(model.manualCheck == nil)
    #expect(model.availableUpdate == v130)
    #expect(updateCheck.callCount == 1)
  }

  @Test("닫은 뒤 다시 열면 진행 중인 요청에 합류한다 (요청 하나)")
  func reopenJoins() async {
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    updateCheck.suspend()
    let model = Self.makeModel(updateCheck: updateCheck)
    let first = await Self.startSuspended(updateCheck) { await model.checkForUpdatesRequested() }
    model.checkWindowClosed()

    let second = Self.start { await model.checkForUpdatesRequested() }
    await Self.waitUntil { model.manualCheck == .checking }
    updateCheck.resume()
    await first.value()
    await second.value()

    #expect(updateCheck.callCount == 1)
    #expect(model.manualCheck == .finished(.newer(v130, current: v120, skipped: false)))
  }

  @Test("창이 최신임을 보이는 동안 자동 확인이 새 버전을 내면 창도 새 버전으로 바뀌고 배너가 보인다")
  func automaticNewerUpdatesWindow() async {
    let updateCheck = UpdateCheckClientFake(result: .success(v120))
    let clock = TestClock()
    let model = Self.makeModel(updateCheck: updateCheck, clock: clock)
    await model.checkForUpdatesRequested()
    #expect(model.manualCheck == .finished(.upToDate(current: v120)))

    updateCheck.setResult(.success(v130))
    clock.advance(by: .day)
    await model.appBecameActive()

    #expect(model.manualCheck == .finished(.newer(v130, current: v120, skipped: false)))
    #expect(model.availableUpdate == v130)
  }

  @Test("창이 새 버전을 보이는 동안 자동 확인이 오프라인으로 실패하면 창과 배너가 그대로다")
  func automaticFailureKeepsWindow() async {
    let updateCheck = UpdateCheckClientFake(result: .success(v130))
    let clock = TestClock()
    let model = Self.makeModel(updateCheck: updateCheck, clock: clock)
    await model.checkForUpdatesRequested()

    updateCheck.setResult(.failure(.offline))
    clock.advance(by: .day)
    await model.appBecameActive()

    #expect(updateCheck.callCount == 2)
    #expect(model.manualCheck == .finished(.newer(v130, current: v120, skipped: false)))
    #expect(model.availableUpdate == v130)
  }

  @Test("창이 확인 중이면 실패도 창에 보인다")
  func failureWhileChecking() async {
    let updateCheck = UpdateCheckClientFake(result: .failure(.offline))
    updateCheck.suspend()
    let model = Self.makeModel(updateCheck: updateCheck)
    let automatic = await Self.startSuspended(updateCheck) { await model.appLaunched() }
    let manual = Self.start { await model.checkForUpdatesRequested() }
    await Self.waitUntil { model.manualCheck == .checking }

    updateCheck.resume()
    await automatic.value()
    await manual.value()

    #expect(model.manualCheck == .finished(.failed(.offline)))
  }
}
