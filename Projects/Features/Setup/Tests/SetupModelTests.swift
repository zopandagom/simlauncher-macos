import Core
import DevEnvironmentInterface
import DevEnvironmentTesting
import Testing
@testable import SetupFeature

@MainActor
struct SetupModelTests: SetupModelTesting {
  nonisolated static let notReadyStatuses: [DevEnvironmentStatus] = [
    .xcodeNotInstalled, .commandLineToolsOnly, .licenseNotAccepted(.sample), .firstLaunchRequired(.sample),
  ]

  @Test("만든 직후에는 확인 전이고 Client 를 부르지 않는다")
  func initialState() {
    let fake = DevEnvironmentClientFake()
    let model = Self.makeModel(fake)

    #expect(model.checkState == .checking)
    #expect(!model.isChecking)
    #expect(!model.isOpening)
    #expect(model.notice == nil)
    #expect(!model.isFinished)
    #expect(model.steps.isEmpty)
    #expect(model.runtimeState == .notChecked)
    #expect(model.runtimeInstall == nil)
    #expect(model.lastInstallResult == nil)
    #expect(!model.isVerifyingInstall)
    #expect(model.terminationAction == .terminateNow)
    #expect(fake.calls.isEmpty)
  }

  @Test("첫 확인 중에는 확인 중으로 보이고 단계가 없다")
  func firstCheckInProgress() async {
    let fake = DevEnvironmentClientFake()
    fake.suspendChecks()
    let model = Self.makeModel(fake)

    let appear = Self.start { await model.onAppear() }
    await Self.waitUntil { fake.calls == [.checkEnvironment] }

    #expect(model.isChecking)
    #expect(!model.canRecheck)
    #expect(model.checkState == .checking)
    #expect(model.steps.isEmpty)
    #expect(!model.canFinish)

    fake.resumeChecks()
    await appear.value()
    #expect(!model.isChecking)
  }

  @Test("첫 판정이 준비됨이면 곧바로 끝난다")
  func firstCheckReadyFinishes() async {
    let (model, fake) = await Self.checkedModel(.ready(.sample))

    #expect(model.isFinished)
    #expect(model.checkState == .checked(.ready(.sample)))
    #expect(fake.calls == [.checkEnvironment, .defaultIOSRuntime])
  }

  @Test("첫 판정이 미준비면 끝나지 않고 그 상태를 보인다", arguments: notReadyStatuses)
  func firstCheckNotReady(status: DevEnvironmentStatus) async {
    let (model, _) = await Self.checkedModel(status)

    #expect(!model.isFinished)
    #expect(model.checkState == .checked(status))
    #expect(model.steps == SetupStep.steps(for: status, runtime: .notChecked))
    #expect(!model.canFinish)
  }

  @Test("첫 확인이 실패하면 실패를 보이고 끝나지 않는다")
  func firstCheckFails() async {
    let (model, _) = await Self.checkedModel(.ready(.sample)) { $0.setCheckError(.checkFailed) }

    #expect(model.checkState == .failed(.checkFailed))
    #expect(!model.isFinished)
    #expect(model.steps.isEmpty)
  }

  @Test("미준비에서 다시 확인해 준비됨이 되면 완료 화면이고 자동으로 끝나지 않는다")
  func recheckToReadyDoesNotAutoFinish() async {
    let (model, fake) = await Self.checkedModel(.licenseNotAccepted(.sample))
    fake.setStatus(.ready(.sample))

    await model.recheckButtonTapped()

    #expect(model.checkState == .checked(.ready(.sample)))
    #expect(!model.isFinished)
    #expect(model.canFinish)
    #expect(Self.checkCount(in: fake) == 2)
  }

  @Test("첫 확인이 실패한 뒤 준비됨으로 확인돼도 자동으로 끝나지 않는다")
  func recheckAfterFailureDoesNotAutoFinish() async {
    let (model, fake) = await Self.checkedModel(.ready(.sample)) { $0.setCheckError(.checkFailed) }
    fake.setCheckError(nil)

    await model.recheckButtonTapped()

    #expect(model.checkState == .checked(.ready(.sample)))
    #expect(!model.isFinished)
  }

  @Test("앱이 다시 활성화되면 한 번 확인하고 결과를 반영한다")
  func appBecameActiveChecks() async {
    let (model, fake) = await Self.checkedModel(.xcodeNotInstalled)
    fake.setStatus(.licenseNotAccepted(.sample))

    await model.appBecameActive()

    #expect(Self.checkCount(in: fake) == 2)
    #expect(model.checkState == .checked(.licenseNotAccepted(.sample)))
  }

  @Test("다시 확인이 실패하면 이전 결과 대신 실패를 보이고, 다시 성공하면 결과로 돌아온다")
  func recheckFailureReplacesResult() async {
    let (model, fake) = await Self.checkedModel(.firstLaunchRequired(.sample))
    fake.setCheckError(.checkFailed)

    await model.recheckButtonTapped()
    #expect(model.checkState == .failed(.checkFailed))
    #expect(model.steps.isEmpty)

    fake.setCheckError(nil)
    await model.recheckButtonTapped()
    #expect(model.checkState == .checked(.firstLaunchRequired(.sample)))
  }

  @Test("기기 목록 열기는 준비됨일 때만 끝낸다")
  func doneButtonOnlyWhenReady() async {
    let (ready, fake) = await Self.checkedModel(.xcodeNotInstalled)
    fake.setStatus(.ready(.sample))
    await ready.recheckButtonTapped()
    ready.doneButtonTapped()
    #expect(ready.isFinished)

    for status in Self.notReadyStatuses {
      let (model, _) = await Self.checkedModel(status)
      model.doneButtonTapped()
      #expect(!model.isFinished, "\(status)")
    }

    let (failed, _) = await Self.checkedModel(.ready(.sample)) { $0.setCheckError(.checkFailed) }
    failed.doneButtonTapped()
    #expect(!failed.isFinished)

    let checking = Self.makeModel(DevEnvironmentClientFake())
    checking.doneButtonTapped()
    #expect(!checking.isFinished)
  }

  @Test("준비됨이어도 다시 확인 중이면 기기 목록 열기가 끝내지 않는다")
  func doneButtonIgnoredWhileRechecking() async {
    let (model, fake) = await Self.checkedModel(.xcodeNotInstalled)
    fake.setStatus(.ready(.sample))
    await model.recheckButtonTapped()
    fake.suspendChecks()

    let recheck = Self.start { await model.recheckButtonTapped() }
    await Self.waitUntil { Self.checkCount(in: fake) == 3 }
    #expect(!model.canFinish)
    model.doneButtonTapped()
    #expect(!model.isFinished)

    fake.resumeChecks()
    await recheck.value()
    #expect(model.canFinish)
  }

  @Test("App Store 열기가 성공하면 알림 없이 끝나고 다시 확인하지 않는다")
  func openAppStoreSucceeds() async {
    let (model, fake) = await Self.checkedModel(.xcodeNotInstalled)

    await model.openAppStoreButtonTapped()

    #expect(fake.calls == [.checkEnvironment, .openXcodeInAppStore])
    #expect(model.notice == nil)
    #expect(!model.isOpening)
  }

  @Test("App Store 열기가 실패하면 알림을 띄운다")
  func openAppStoreFails() async {
    let (model, fake) = await Self.checkedModel(.xcodeNotInstalled) { $0.setOpenAppStoreError(.openFailed) }

    await model.openAppStoreButtonTapped()

    #expect(model.notice == .openAppStoreFailed(.openFailed))
    #expect(!model.isOpening)
    #expect(Self.checkCount(in: fake) == 1)
  }

  @Test("Xcode 열기가 성공하면 알림 없이 끝나고 다시 확인하지 않는다")
  func openXcodeSucceeds() async {
    let (model, fake) = await Self.checkedModel(.licenseNotAccepted(.sample))

    await model.openXcodeButtonTapped()

    #expect(fake.calls == [.checkEnvironment, .openXcode])
    #expect(model.notice == nil)
    #expect(!model.isOpening)
  }

  @Test("Xcode 열기가 열기 실패면 알림만 띄운다")
  func openXcodeOpenFailed() async {
    let (model, fake) = await Self.checkedModel(.firstLaunchRequired(.sample)) { $0.setOpenXcodeError(.openFailed) }

    await model.openXcodeButtonTapped()

    #expect(model.notice == .openXcodeFailed(.openFailed))
    #expect(fake.calls == [.checkEnvironment, .openXcode])
    #expect(model.checkState == .checked(.firstLaunchRequired(.sample)))
    #expect(!model.isOpening)
  }

  @Test("Xcode 가 없어졌으면 알림을 띄우고 다시 확인해 설치 단계로 바꾼다")
  func openXcodeNotFoundRechecks() async {
    let (model, fake) = await Self.checkedModel(.licenseNotAccepted(.sample))
    fake.setStatus(.xcodeNotInstalled)

    await model.openXcodeButtonTapped()

    #expect(model.notice == .openXcodeFailed(.xcodeNotFound))
    #expect(fake.calls == [.checkEnvironment, .openXcode, .checkEnvironment])
    #expect(model.checkState == .checked(.xcodeNotInstalled))
    #expect(!model.isOpening)
  }

  @Test("Xcode 가 없어져 다시 확인하는 동안 여는 중 표시는 이미 풀려 있다")
  func openXcodeNotFoundReleasesOpeningBeforeCheck() async {
    let (model, fake) = await Self.checkedModel(.licenseNotAccepted(.sample))
    fake.setStatus(.xcodeNotInstalled)
    fake.suspendChecks()

    let open = Self.start { await model.openXcodeButtonTapped() }
    await Self.waitUntil { Self.checkCount(in: fake) == 2 }

    #expect(!model.isOpening)
    #expect(model.isChecking)

    fake.resumeChecks()
    await open.value()
    #expect(model.checkState == .checked(.xcodeNotInstalled))
  }

  @Test("알림을 닫으면 없어진다")
  func noticeDismissed() async {
    let (model, _) = await Self.checkedModel(.xcodeNotInstalled) { $0.setOpenAppStoreError(.openFailed) }
    await model.openAppStoreButtonTapped()

    model.noticeDismissed()

    #expect(model.notice == nil)
  }

  @Test("다시 열면 끝나지 않은 상태가 되고, 이어서 준비됨으로 확인돼도 자동으로 끝나지 않는다")
  func reopenedDoesNotAutoFinish() async {
    let (model, fake) = await Self.checkedModel(.ready(.sample))
    #expect(model.isFinished)

    model.reopened()
    #expect(!model.isFinished)
    #expect(model.checkState == .checked(.ready(.sample)))

    await model.onAppear()
    #expect(!model.isFinished)
    #expect(model.canFinish)
    #expect(Self.checkCount(in: fake) == 2)
  }
}
