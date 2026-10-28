import AndroidSDKInterface
import AndroidSDKTesting
import Core
import Foundation
import PreferencesTesting
import Testing
import WorkspaceTesting
@testable import AndroidSetupFeature

/// 기기 목록으로 넘어가기: 첫 확인 자동 전환(`isFinished`), "기기 목록 열기"(`canOpenDeviceList`·`deviceListButtonTapped`),
/// 기기 목록에서 돌아오기(`reopened`).
@MainActor
struct AndroidSetupDeviceListTests: AndroidSetupTesting {
  @Test("첫 확인이 셋 다 설치됨이면 곧바로 기기 목록으로 넘어간다")
  func firstReadyCheckFinishes() async {
    let setup = await Self.checkedFixture(.readySample)
    #expect(setup.model.isFinished)
    #expect(setup.model.canOpenDeviceList)
  }

  @Test(
    "첫 확인이 셋 다 설치됨이 아니면 넘어가지 않고 기기 목록을 열 수 없다",
    arguments: [
      AndroidSDKStatus.absentSample, .partialSample, .chosenMissingSample, .unusableSample(.unreadable),
    ]
  )
  func notReadyStays(status: AndroidSDKStatus) async {
    let setup = await Self.checkedFixture(status)
    #expect(!setup.model.isFinished)
    #expect(!setup.model.canOpenDeviceList)
    setup.model.deviceListButtonTapped()
    #expect(!setup.model.isFinished)
  }

  @Test("첫 확인 뒤 다시 확인으로 셋 다 설치됨이 되면 자동으로 넘어가지 않고 버튼으로 넘어간다")
  func laterReadyNeedsButton() async {
    let setup = await Self.checkedFixture(.partialSample)
    setup.fake.setStatus(.readySample)
    await setup.model.recheckButtonTapped()
    #expect(!setup.model.isFinished)
    #expect(setup.model.canOpenDeviceList)
    setup.model.deviceListButtonTapped()
    #expect(setup.model.isFinished)
  }

  @Test("설치가 끝나 셋 다 설치됨이 되면 결과 줄을 보이고 버튼으로 넘어간다")
  func installThenOpen() async {
    let setup = await Self.checkedFixture(preferences: Self.acceptedPreferences())
    setup.fake.setStatus(.readySample)
    await setup.model.installButtonTapped()
    #expect(setup.model.lastResult != nil)
    #expect(!setup.model.isFinished)
    #expect(setup.model.canOpenDeviceList)
    setup.model.deviceListButtonTapped()
    #expect(setup.model.isFinished)
  }

  @Test("확인 중에는 기기 목록을 열 수 없다")
  func checkingBlocksOpen() async {
    let setup = await Self.checkedFixture(.partialSample)
    setup.fake.setStatus(.readySample)
    await setup.model.recheckButtonTapped()
    setup.fake.suspendChecks()
    let recheck = Self.start { await setup.model.recheckButtonTapped() }
    await Self.waitUntil { setup.fake.suspendedCheckCount == 1 }
    #expect(!setup.model.canOpenDeviceList)
    setup.model.deviceListButtonTapped()
    #expect(!setup.model.isFinished)
    setup.fake.resumeChecks()
    await recheck.value()
    #expect(setup.model.canOpenDeviceList)
  }

  @Test("설치 중에는 기기 목록을 열 수 없다")
  func installingBlocksOpen() async {
    let (setup, task) = await Self.suspendedInstall()
    #expect(!setup.model.canOpenDeviceList)
    setup.model.deviceListButtonTapped()
    #expect(!setup.model.isFinished)
    setup.fake.resumeInstalls()
    await task.value()
  }

  @Test("이미 셋 다 설치된 상태에서 다시 열면 도구 화면이 보이고, 다시 확인 뒤 기기 목록을 열 수 있다")
  func reopenedWhenReady() async {
    let setup = await Self.checkedFixture(.readySample)
    #expect(setup.model.isFinished)
    setup.model.reopened()
    #expect(!setup.model.isFinished)
    // 다시 나타난 도구 화면의 onAppear 가 확인한다. 첫 확인이 아니라 자동으로 넘어가지 않는다.
    await setup.model.onAppear()
    #expect(!setup.model.isFinished)
    #expect(setup.model.canOpenDeviceList)
    setup.model.deviceListButtonTapped()
    #expect(setup.model.isFinished)
  }

  @Test("다시 열면 지난 설치 결과를 지운다")
  func reopenedClearsResult() async {
    let setup = await Self.checkedFixture(preferences: Self.acceptedPreferences())
    setup.fake.setStatus(.readySample)
    await setup.model.installButtonTapped()
    setup.model.deviceListButtonTapped()
    #expect(setup.model.lastResult != nil)
    setup.model.reopened()
    #expect(setup.model.lastResult == nil)
    #expect(!setup.model.isFinished)
  }
}
