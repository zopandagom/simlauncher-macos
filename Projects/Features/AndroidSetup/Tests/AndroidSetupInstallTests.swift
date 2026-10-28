import AndroidSDKInterface
import AndroidSDKTesting
import Core
import Foundation
import PreferencesTesting
import Testing
@testable import AndroidSetupFeature

/// 계획 받기·동의·설치·취소.
@MainActor
struct AndroidSetupInstallTests: AndroidSetupTesting {
  private static let allFingerprints = Set(AndroidSDKInstallPlan.sample.licenses.map(\.fingerprint))

  // MARK: - 계획

  @Test("동의 기록에 없는 원문이 있으면 계획을 받아 동의를 기다린다")
  func planNeedsConsent() async {
    let setup = await Self.awaitingConsentFixture()
    #expect(setup.model.plan == .awaitingConsent(.sample, toConfirm: [.sdkSample, .armDBTSample]))
    #expect(setup.model.isPlanning)
    #expect(!setup.model.canInstall)
    #expect(!setup.model.canRecheck)
    #expect(Self.installCalls(in: setup.fake).isEmpty)
  }

  @Test("이미 동의한 원문은 다시 묻지 않는다 (동의할 원문만 시트에 보인다)")
  func partlyAcceptedAsksOnlyNew() async {
    let preferences = PreferencesClientFake(
      androidSDKPath: .absent,
      androidLicenses: [AndroidLicense.sdkSample.fingerprint]
    )
    let setup = await Self.awaitingConsentFixture(preferences: preferences)
    #expect(setup.model.plan == .awaitingConsent(.sample, toConfirm: [.armDBTSample]))
  }

  @Test("모두 동의한 원문이면 시트 없이 바로 설치하고, 끝나면 다시 확인한다")
  func acceptedInstallsDirectly() async {
    let setup = await Self.checkedFixture(preferences: Self.acceptedPreferences())
    setup.fake.setStatus(.readySample)
    await setup.model.installButtonTapped()
    #expect(Self.installCalls(in: setup.fake) == [Self.allFingerprints])
    #expect(setup.model.plan == nil)
    #expect(setup.model.install == nil)
    #expect(setup.model.lastResult?.kind == .finished(
      AndroidSDKInstallOutcome(installed: [.platformTools, .emulator, .systemImage], alreadyPresent: [])
    ))
    #expect(setup.model.lastResult?.root == .sample)
    #expect(setup.model.checkState == .checked(.readySample))
    #expect(!setup.model.isVerifyingInstall)
    #expect(Self.count(.checkSDK, in: setup.fake) == 2)
  }

  @Test("빈 계획이면 설치하지 않고 다시 확인한다")
  func emptyPlanRechecks() async {
    let setup = await Self.checkedFixture { $0.setPlanResult(.success(.emptySample)) }
    setup.fake.setStatus(.readySample)
    await setup.model.installButtonTapped()
    #expect(setup.model.plan == nil)
    #expect(Self.installCalls(in: setup.fake).isEmpty)
    #expect(setup.model.checkState == .checked(.readySample))
  }

  @Test(
    "계획을 만들지 못하면 실패 줄을 보이고, 설치 버튼이 다시 시도한다",
    arguments: [
      AndroidSDKPlanError.download(.offline), .download(.httpStatus(503)), .repositoryUnreadable,
      .noCompatiblePackage(.systemImage), .sdkFolderUnavailable,
    ]
  )
  func planFailure(error: AndroidSDKPlanError) async {
    let setup = await Self.checkedFixture { $0.setPlanResult(.failure(error)) }
    await setup.model.installButtonTapped()
    #expect(setup.model.plan == .failed(error))
    #expect(setup.model.canInstall)
    #expect(setup.model.canRecheck)
    setup.fake.setPlanResult(.success(.sample))
    await setup.model.installButtonTapped()
    #expect(setup.model.plan == .awaitingConsent(.sample, toConfirm: [.sdkSample, .armDBTSample]))
    #expect(Self.count(.fetchInstallPlan, in: setup.fake) == 2)
  }

  @Test("계획을 받는 중에는 확인·설치를 다시 시작하지 않는다")
  func planFetchGuards() async {
    let setup = await Self.checkedFixture { $0.suspendPlans() }
    let install = Self.start { await setup.model.installButtonTapped() }
    await Self.waitUntil { setup.fake.suspendedPlanCount == 1 }
    #expect(!setup.model.canInstall)
    await setup.model.installButtonTapped()
    await setup.model.recheckButtonTapped()
    await setup.model.appBecameActive()
    await setup.model.onAppear()
    #expect(Self.count(.fetchInstallPlan, in: setup.fake) == 1)
    #expect(Self.count(.checkSDK, in: setup.fake) == 1)
    #expect(Self.count(.removeLeftovers, in: setup.fake) == 1)
    #expect(setup.model.terminationAction == .terminateNow)
    setup.fake.resumePlans()
    await install.value()
  }

  @Test("계획 받기를 취소하면 계획이 사라지고, 늦게 온 취소 결과가 새 받기를 지우지 않는다")
  func planCancel() async {
    let setup = await Self.checkedFixture { $0.suspendPlans() }
    let first = Self.start { await setup.model.installButtonTapped() }
    await Self.waitUntil { setup.fake.suspendedPlanCount == 1 }
    setup.model.planCancelButtonTapped()
    #expect(setup.model.plan == nil)
    #expect(setup.model.canInstall)
    let second = Self.start { await setup.model.installButtonTapped() }
    await first.value()
    await Self.waitUntil { setup.fake.suspendedPlanCount == 1 }
    #expect(setup.model.plan == .fetching)
    setup.fake.resumePlans()
    await second.value()
    #expect(setup.model.plan == .awaitingConsent(.sample, toConfirm: [.sdkSample, .armDBTSample]))
  }

  @Test("동의 시트를 닫으면 동의하지 않고 계획을 버린다")
  func consentDismissed() async {
    let setup = await Self.awaitingConsentFixture()
    setup.model.planCancelButtonTapped()
    #expect(setup.model.plan == nil)
    #expect(setup.model.canInstall)
    #expect(setup.preferences.storedAndroidLicenses.isEmpty)
    #expect(Self.installCalls(in: setup.fake).isEmpty)
  }

  @Test("계획 실패 줄은 취소 버튼으로 지우지 않는다")
  func planCancelKeepsFailure() async {
    let setup = await Self.checkedFixture { $0.setPlanResult(.failure(.repositoryUnreadable)) }
    await setup.model.installButtonTapped()
    setup.model.planCancelButtonTapped()
    #expect(setup.model.plan == .failed(.repositoryUnreadable))
  }

  // MARK: - 동의

  @Test("동의하면 시트의 원문 지문을 기록하고, 기록과 계획 지문을 넘겨 설치한다")
  func licenseAcceptedRecordsAndInstalls() async {
    let setup = await Self.awaitingConsentFixture()
    await setup.model.licenseAccepted()
    #expect(setup.preferences.calls.contains(.addAcceptedAndroidLicenses(Self.allFingerprints)))
    #expect(setup.preferences.storedAndroidLicenses == Self.allFingerprints)
    #expect(Self.installCalls(in: setup.fake) == [Self.allFingerprints])
    #expect(setup.model.plan == nil)
    #expect(setup.model.lastResult?.kind == .finished(
      AndroidSDKInstallOutcome(installed: [.platformTools, .emulator, .systemImage], alreadyPresent: [])
    ))
    #expect(Self.count(.checkSDK, in: setup.fake) == 2)
  }

  @Test("동의 기록이 관리자 잠김이어도 알림 없이 설치는 끝까지 한다")
  func licenseAcceptedWhenLocked() async {
    let preferences = PreferencesClientFake(androidSDKPath: .absent, androidLicenses: [], androidLicensesLocked: true)
    let setup = await Self.awaitingConsentFixture(preferences: preferences)
    await setup.model.licenseAccepted()
    #expect(setup.preferences.storedAndroidLicenses.isEmpty)
    #expect(Self.installCalls(in: setup.fake) == [Self.allFingerprints])
    #expect(setup.model.lastResult?.kind == .finished(
      AndroidSDKInstallOutcome(installed: [.platformTools, .emulator, .systemImage], alreadyPresent: [])
    ))
    #expect(setup.model.notice == nil)
  }

  @Test("동의를 기다리지 않을 때의 동의는 무시한다")
  func licenseAcceptedIgnoredOtherwise() async {
    let setup = await Self.checkedFixture()
    await setup.model.licenseAccepted()
    #expect(Self.installCalls(in: setup.fake).isEmpty)
    let recorded = setup.preferences.calls.contains { call in
      if case .addAcceptedAndroidLicenses = call {
        return true
      }
      return false
    }
    #expect(!recorded)
  }

  // MARK: - 설치

  @Test("설치 중에는 진행을 보이고 확인·설치를 다시 시작하지 않는다")
  func installProgressAndGuards() async {
    let (setup, install) = await Self.suspendedInstall()
    #expect(setup.model.install?.progress == .firstSample)
    #expect(setup.model.install?.plan == .sample)
    await setup.fake.sendInstallProgress(.at(2, .extracting))
    #expect(setup.model.install?.progress == .at(2, .extracting))
    #expect(!setup.model.canInstall)
    #expect(!setup.model.canRecheck)
    await setup.model.recheckButtonTapped()
    await setup.model.appBecameActive()
    await setup.model.onAppear()
    await setup.model.installButtonTapped()
    #expect(Self.count(.checkSDK, in: setup.fake) == 1)
    #expect(Self.count(.removeLeftovers, in: setup.fake) == 1)
    #expect(Self.count(.fetchInstallPlan, in: setup.fake) == 1)
    setup.fake.resumeInstalls()
    await install.value()
  }

  @Test("설치가 끝나면 다시 확인이 끝날 때까지 결과를 확인하는 중이다")
  func verifyingAfterInstall() async {
    let (setup, install) = await Self.suspendedInstall()
    setup.fake.suspendChecks()
    setup.fake.resumeInstalls()
    await Self.waitUntil { setup.fake.suspendedCheckCount == 1 }
    #expect(setup.model.install == nil)
    #expect(setup.model.isVerifyingInstall)
    #expect(!setup.model.canInstall)
    setup.fake.resumeChecks()
    await install.value()
    #expect(!setup.model.isVerifyingInstall)
  }

  @Test(
    "설치가 실패해도 결과를 남기고 다시 확인한다",
    arguments: [
      AndroidSDKInstallError.download(.systemImage, .connectionLost), .checksumMismatch(.emulator),
      .archiveUnsafe(.systemImage), .insufficientDiskSpace(.systemImage, required: 9_000_000_000, available: nil),
      .destinationExists(.emulator), .sdkFolderUnavailable, .sdkLocationChanged, .licenseNotAccepted,
    ]
  )
  func installFailure(error: AndroidSDKInstallError) async {
    let setup = await Self.checkedFixture(preferences: Self.acceptedPreferences()) {
      $0.setInstallScript(progress: [], result: .failure(error))
    }
    await setup.model.installButtonTapped()
    #expect(setup.model.lastResult?.kind == .failed(error))
    #expect(setup.model.install == nil)
    #expect(Self.count(.checkSDK, in: setup.fake) == 2)
    #expect(setup.model.canInstall)
  }

  @Test("새 설치를 시작하면 지난 결과를 지운다")
  func newInstallClearsResult() async {
    let setup = await Self.checkedFixture(preferences: Self.acceptedPreferences()) {
      $0.setInstallScript(progress: [], result: .failure(.cancelled))
    }
    await setup.model.installButtonTapped()
    #expect(setup.model.lastResult != nil)
    setup.fake.suspendPlans()
    let install = Self.start { await setup.model.installButtonTapped() }
    await Self.waitUntil { setup.fake.suspendedPlanCount == 1 }
    #expect(setup.model.lastResult == nil)
    setup.fake.resumePlans()
    await install.value()
  }

  @Test("받기·확인·풀기 중에는 취소할 수 있고, 취소하면 멈춘 뒤 다시 확인한다")
  func cancelInstall() async {
    let (setup, install) = await Self.suspendedInstall()
    #expect(setup.model.canCancelInstall)
    setup.model.cancelInstallButtonTapped()
    #expect(setup.model.install?.isCancelling == true)
    #expect(!setup.model.canCancelInstall)
    await install.value()
    #expect(setup.model.lastResult?.kind == .failed(.cancelled))
    #expect(Self.count(.checkSDK, in: setup.fake) == 2)
  }

  @Test("마무리 단계에서는 취소 버튼이 듣지 않는다")
  func cannotCancelFinishing() async {
    let (setup, install) = await Self.suspendedInstall(progress: [.at(1, .finishing)])
    #expect(!setup.model.canCancelInstall)
    setup.model.cancelInstallButtonTapped()
    #expect(setup.model.install?.isCancelling == false)
    setup.fake.resumeInstalls()
    await install.value()
    #expect(setup.model.lastResult?.kind != .failed(.cancelled))
  }
}
