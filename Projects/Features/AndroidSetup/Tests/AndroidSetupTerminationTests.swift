import AndroidSDKInterface
import AndroidSDKTesting
import Core
import Foundation
import Observation
import PreferencesTesting
import Synchronization
import Testing
@testable import AndroidSetupFeature

/// 설치·계획·동의 중 앱 종료.
@MainActor
struct AndroidSetupTerminationTests: AndroidSetupTesting {
  // MARK: - 앱 종료

  @Test("종료 동작: 설치 중이 아니면 바로, 받기 중이면 묻고, 마무리·멈추는 중이면 기다린다")
  func terminationActions() async {
    let idle = await Self.checkedFixture()
    #expect(idle.model.terminationAction == .terminateNow)
    let consent = await Self.awaitingConsentFixture()
    #expect(consent.model.terminationAction == .terminateNow)

    let (setup, install) = await Self.suspendedInstall()
    #expect(setup.model.terminationAction == .confirmThenCancel)
    await setup.fake.sendInstallProgress(.at(3, .finishing))
    #expect(setup.model.terminationAction == .waitForInstall)
    await setup.fake.sendInstallProgress(.at(3, .extracting))
    #expect(setup.model.terminationAction == .confirmThenCancel)
    setup.model.cancelInstallButtonTapped()
    #expect(setup.model.terminationAction == .waitForInstall)
    await install.value()
  }

  @Test("받는 중에 종료를 확정하면 설치를 취소하고 끝나기를 기다리며, 끝난 뒤 다시 확인하지 않는다")
  func terminationCancelsDownload() async {
    let (setup, install) = await Self.suspendedInstall()
    await setup.model.appTerminationRequested()
    #expect(setup.model.install == nil)
    #expect(setup.model.lastResult?.kind == .failed(.cancelled))
    #expect(!setup.model.isVerifyingInstall)
    #expect(Self.count(.checkSDK, in: setup.fake) == 1)
    await install.value()
    // 종료를 확정한 뒤에는 확인·설치를 시작하지 않는다.
    await setup.model.recheckButtonTapped()
    await setup.model.onAppear()
    #expect(Self.count(.checkSDK, in: setup.fake) == 1)
    #expect(!setup.model.canInstall)
  }

  @Test("종료 확정의 취소 표시는 첫 대기 전에 끝난다 (App 이 다른 대기와 함께 시작해도 곧바로 멈춘다)")
  func terminationMarksBeforeFirstWait() async {
    let (setup, install) = await Self.suspendedInstall()
    let termination = Task.immediate { await setup.model.appTerminationRequested() }
    // 사이에 await 가 없다: 아래 상태는 `Task.immediate` 가 첫 대기에서 돌려준 시점의 것이다.
    #expect(setup.model.install?.endsWithTermination == true)
    #expect(setup.model.install?.isCancelling == true)
    #expect(!setup.model.canCancelInstall)
    #expect(setup.model.terminationAction == .waitForInstall)
    #expect(!setup.model.canInstall)
    #expect(!setup.model.canRecheck)
    await termination.value
    #expect(setup.model.install == nil)
    #expect(setup.model.lastResult?.kind == .failed(.cancelled))
    #expect(Self.count(.checkSDK, in: setup.fake) == 1)
    await install.value()
  }

  @Test("설치 중이 아닐 때 종료를 확정하면 확인·설치 버튼이 꺼지고 눌러도 아무것도 하지 않는다")
  func terminationWhileIdleDisablesActions() async {
    let setup = await Self.checkedFixture()
    #expect(setup.model.canInstall)
    #expect(setup.model.canRecheck)
    await setup.model.appTerminationRequested()
    #expect(!setup.model.canInstall)
    #expect(!setup.model.canRecheck)
    let checks = Self.count(.checkSDK, in: setup.fake)
    let plans = Self.count(.fetchInstallPlan, in: setup.fake)
    await setup.model.installButtonTapped()
    await setup.model.recheckButtonTapped()
    await setup.model.appBecameActive()
    #expect(Self.count(.checkSDK, in: setup.fake) == checks)
    #expect(Self.count(.fetchInstallPlan, in: setup.fake) == plans)
    #expect(setup.model.plan == nil)
  }

  @Test("종료 중 상태 변경은 관찰된다 (설치 중이 아니어도 화면이 버튼을 다시 그린다)")
  func terminationIsObserved() async {
    let setup = await Self.checkedFixture()
    let changed = ObservationChange()
    withObservationTracking {
      _ = setup.model.canInstall
    } onChange: {
      changed.mark()
    }
    await setup.model.appTerminationRequested()
    #expect(changed.isMarked)
  }

  @Test("마무리 단계에서 종료를 확정해도 설치 Task 를 취소한다 (다음 패키지를 시작하지 않게)")
  func terminationCancelsFinishing() async {
    let (setup, install) = await Self.suspendedInstall(progress: [.at(1, .finishing)])
    #expect(setup.model.terminationAction == .waitForInstall)
    // Fake 의 멈춘 설치는 재개하지 않으면 취소로만 끝난다: 끝났으면 Model 이 마무리 단계에서도 Task 를 취소한 것이다
    // (Impl 은 마무리를 끝낸 뒤 다음 패키지 시작에서 `.cancelled`).
    await setup.model.appTerminationRequested()
    await install.value()
    #expect(setup.model.lastResult?.kind == .failed(.cancelled))
  }

  @Test("계획을 받는 중에 종료를 확정하면 받기를 취소하고 기다리지 않는다")
  func terminationDuringPlan() async {
    let setup = await Self.checkedFixture { $0.suspendPlans() }
    let install = Self.start { await setup.model.installButtonTapped() }
    await Self.waitUntil { setup.fake.suspendedPlanCount == 1 }
    await setup.model.appTerminationRequested()
    #expect(setup.model.plan == nil)
    await install.value()
    #expect(setup.model.plan == nil)
    #expect(Self.installCalls(in: setup.fake).isEmpty)
  }

  @Test("동의 대기 중에 종료를 확정하면 동의 시트를 닫고, 그 뒤 동의는 무시한다")
  func terminationDuringConsent() async {
    let setup = await Self.awaitingConsentFixture()
    await setup.model.appTerminationRequested()
    #expect(setup.model.plan == nil)
    await setup.model.licenseAccepted()
    #expect(Self.installCalls(in: setup.fake).isEmpty)
  }
}

/// `withObservationTracking` 의 `onChange`(Sendable 클로저)가 바뀜을 기록하는 상자.
private final class ObservationChange: Sendable {
  private let changed = Mutex(false)

  var isMarked: Bool {
    self.changed.withLock { $0 }
  }

  func mark() {
    self.changed.withLock { $0 = true }
  }
}
