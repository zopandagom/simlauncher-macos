import AndroidSDKInterface
import AndroidSDKTesting
import Core
import Foundation
import PreferencesTesting
import Testing
import WorkspaceInterface
import WorkspaceTesting
@testable import AndroidSetupFeature

/// 확인(onAppear·다시 확인·앱 활성화·위치 바뀜)·설치 가능 판정·Finder 보이기.
@MainActor
struct AndroidSetupModelTests: AndroidSetupTesting {
  @Test("화면이 보이면 남은 스테이징·받기 폴더를 지운 뒤 확인한다")
  func onAppearRemovesLeftoversThenChecks() async {
    let setup = await Self.checkedFixture()
    #expect(setup.fake.calls == [.removeLeftovers, .checkSDK])
    #expect(setup.model.checkState == .checked(.absentSample))
    #expect(!setup.model.isChecking)
    #expect(setup.model.canInstall)
  }

  @Test("첫 확인 전에는 확인 중이고 설치할 수 없다")
  func initialStateIsChecking() {
    let model = AndroidSetupModel(
      androidSDK: AndroidSDKClientFake(),
      preferences: PreferencesClientFake(),
      workspace: WorkspaceClientFake()
    )
    #expect(model.checkState == .checking)
    #expect(!model.canInstall)
    #expect(model.terminationAction == .terminateNow)
  }

  @Test("다시 확인과 앱 활성화는 바뀐 상태를 읽는다 (남은 폴더 정리는 화면이 보일 때만)")
  func recheckAndActivationReadStatus() async {
    let setup = await Self.checkedFixture()
    setup.fake.setStatus(.readySample)
    await setup.model.recheckButtonTapped()
    #expect(setup.model.checkState == .checked(.readySample))
    setup.fake.setStatus(.partialSample)
    await setup.model.appBecameActive()
    #expect(setup.model.checkState == .checked(.partialSample))
    #expect(Self.count(.removeLeftovers, in: setup.fake) == 1)
    #expect(Self.count(.checkSDK, in: setup.fake) == 3)
  }

  @Test("확인 중에 다시 요청하면 끝난 뒤 한 번 더 확인한다")
  func recheckDuringCheckRunsOnceMore() async {
    let setup = await Self.checkedFixture()
    setup.fake.suspendChecks()
    let first = Self.start { await setup.model.recheckButtonTapped() }
    await Self.waitUntil { setup.fake.suspendedCheckCount == 1 }
    #expect(setup.model.isChecking)
    #expect(!setup.model.canRecheck)
    #expect(!setup.model.canInstall)
    let second = Self.start { await setup.model.appBecameActive() }
    await Task.yield()
    setup.fake.setStatus(.readySample)
    setup.fake.resumeChecks()
    await first.value()
    await second.value()
    #expect(Self.count(.checkSDK, in: setup.fake) == 3)
    #expect(setup.model.checkState == .checked(.readySample))
    #expect(!setup.model.isChecking)
  }

  @Test("확인할 때 SDK 위치가 관리자 잠김인지 읽는다")
  func readsLocationLock() async {
    let preferences = PreferencesClientFake(androidSDKPath: AndroidSDKPathSetting(value: .path("/x"), isLocked: true))
    let setup = await Self.checkedFixture(.unusableSample(.missing), preferences: preferences)
    #expect(setup.model.isLocationLocked)
    preferences.setStoredAndroidSDKPath(.absent)
    await setup.model.recheckButtonTapped()
    #expect(!setup.model.isLocationLocked)
  }

  @Test(
    "위치를 쓸 수 없거나 설치를 막는 이유가 있거나 모두 설치됐으면 설치할 수 없다",
    arguments: [
      AndroidSDKStatus.unusableSample(.missing), .unusableSample(.notDirectory), .unusableSample(.brokenLink),
      .unusableSample(.unreadable), .unusableSample(.invalidSetting), .notWritableSample, .readySample,
      AndroidSDKStatus(
        location: .folder(.sample, writable: true),
        components: [.platformTools: .missing, .emulator: .missing, .systemImage: .missing],
        installBlocker: .unsupportedVolume,
        installedSystemImages: []
      ),
    ]
  )
  func cannotInstall(status: AndroidSDKStatus) async {
    let setup = await Self.checkedFixture(status)
    #expect(!setup.model.canInstall)
    await setup.model.installButtonTapped()
    #expect(Self.count(.fetchInstallPlan, in: setup.fake) == 0)
    #expect(setup.model.plan == nil)
  }

  @Test("없는 구성 요소가 있으면 일부가 쓸 수 없어도 설치할 수 있다")
  func partialCanInstall() async {
    let setup = await Self.checkedFixture(.partialSample)
    #expect(setup.model.canInstall)
  }

  // MARK: - 위치 바뀜

  @Test("평소에 위치가 바뀌면 바로 다시 확인한다")
  func locationChangedRechecks() async {
    let setup = await Self.checkedFixture()
    setup.fake.setStatus(.chosenMissingSample)
    await setup.model.sdkLocationChanged()
    #expect(setup.model.checkState == .checked(.chosenMissingSample))
    #expect(Self.count(.checkSDK, in: setup.fake) == 2)
  }

  @Test("확인 중에 위치가 바뀌면 그 확인이 끝난 뒤 한 번 더 확인한다")
  func locationChangedDuringCheck() async {
    let setup = await Self.checkedFixture()
    setup.fake.suspendChecks()
    let check = Self.start { await setup.model.recheckButtonTapped() }
    await Self.waitUntil { setup.fake.suspendedCheckCount == 1 }
    let changed = Self.start { await setup.model.sdkLocationChanged() }
    await Task.yield()
    setup.fake.setStatus(.chosenMissingSample)
    setup.fake.resumeChecks()
    await check.value()
    await changed.value()
    #expect(Self.count(.checkSDK, in: setup.fake) == 3)
    #expect(setup.model.checkState == .checked(.chosenMissingSample))
  }

  @Test("계획을 받는 중에 위치가 바뀌면 받기를 취소하고 다시 확인한다 (늦은 결과로 동의 시트가 뜨지 않는다)")
  func locationChangedDuringPlanFetch() async {
    let setup = await Self.checkedFixture { $0.suspendPlans() }
    let install = Self.start { await setup.model.installButtonTapped() }
    await Self.waitUntil { setup.fake.suspendedPlanCount == 1 }
    #expect(setup.model.plan == .fetching)
    await setup.model.sdkLocationChanged()
    await install.value()
    #expect(setup.model.plan == nil)
    #expect(Self.count(.checkSDK, in: setup.fake) == 2)
    #expect(Self.installCalls(in: setup.fake).isEmpty)
  }

  @Test("동의 대기 중에 위치가 바뀌면 계획을 버리고 다시 확인한다")
  func locationChangedDuringConsent() async {
    let setup = await Self.awaitingConsentFixture()
    await setup.model.sdkLocationChanged()
    #expect(setup.model.plan == nil)
    #expect(Self.count(.checkSDK, in: setup.fake) == 2)
    #expect(setup.preferences.storedAndroidLicenses.isEmpty)
  }

  @Test("계획 실패 줄은 위치가 바뀌면 지운다")
  func locationChangedClearsPlanFailure() async {
    let setup = await Self.checkedFixture { $0.setPlanResult(.failure(.download(.offline))) }
    await setup.model.installButtonTapped()
    #expect(setup.model.plan == .failed(.download(.offline)))
    await setup.model.sdkLocationChanged()
    #expect(setup.model.plan == nil)
  }

  @Test("설치 중에 위치가 바뀌면 확인하지 않고, 끝난 뒤 새 위치로 확인해 결과에 원래 위치를 남긴다")
  func locationChangedDuringInstall() async {
    let (setup, install) = await Self.suspendedInstall()
    let checks = Self.count(.checkSDK, in: setup.fake)
    setup.fake.setStatus(.chosenMissingSample)
    await setup.model.sdkLocationChanged()
    #expect(Self.count(.checkSDK, in: setup.fake) == checks)
    #expect(setup.model.install != nil)
    setup.fake.resumeInstalls()
    await install.value()
    #expect(Self.count(.checkSDK, in: setup.fake) == checks + 1)
    #expect(setup.model.checkState == .checked(.chosenMissingSample))
    #expect(setup.model.lastResult?.root == .sample)
    #expect(setup.model.lastResult?.locationChangedSince == true)
  }

  @Test("같은 위치에 설치했으면 결과에 위치 바뀜이 없다")
  func sameLocationAfterInstall() async {
    let (setup, install) = await Self.suspendedInstall()
    setup.fake.setStatus(.readySample)
    setup.fake.resumeInstalls()
    await install.value()
    #expect(setup.model.lastResult?.locationChangedSince == false)
  }

  // MARK: - Finder

  @Test("쓸 수 없는 위치·구성 요소·막는 폴더를 Finder 에서 보인다")
  func revealTargets() async {
    let setup = await Self.checkedFixture(.unusableSample(.notDirectory))
    await setup.model.revealButtonTapped(.location)
    setup.fake.setStatus(.partialSample)
    await setup.model.recheckButtonTapped()
    await setup.model.revealButtonTapped(.component(.emulator))
    setup.fake.setStatus(.notWritableSample)
    await setup.model.recheckButtonTapped()
    await setup.model.revealButtonTapped(.blockedFolder)
    #expect(setup.workspace.calls == [
      .revealInFinder(AndroidSDKRoot.sample.url),
      .revealInFinder(AndroidSDKRoot.sample.folder(for: .emulator)),
      .revealInFinder(AndroidSDKRoot.sample.url),
    ])
    #expect(setup.model.notice == nil)
  }

  @Test("보일 경로가 없으면(잘못된 설정·막는 이유 없음) Finder 를 부르지 않는다")
  func revealWithoutPath() async {
    let setup = await Self.checkedFixture(.unusableSample(.invalidSetting))
    await setup.model.revealButtonTapped(.location)
    await setup.model.revealButtonTapped(.blockedFolder)
    #expect(setup.workspace.calls.isEmpty)
  }

  @Test("Finder 보이기가 실패하면 알림을 띄우고, 닫으면 지운다")
  func revealFailureNotice() async {
    let setup = await Self.checkedFixture(.partialSample)
    setup.workspace.setRevealError(.fileNotFound)
    await setup.model.revealButtonTapped(.component(.emulator))
    #expect(setup.model.notice == .revealFailed(.fileNotFound))
    setup.model.noticeDismissed()
    #expect(setup.model.notice == nil)
  }
}
