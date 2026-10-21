import Core
import DevEnvironmentInterface
import DevEnvironmentTesting
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import SetupFeature

/// 기본 iOS 런타임 설치: 진행·취소·결과·다시 확인, 설치 중 막는 동작.
@MainActor
struct SetupInstallTests: SetupModelTesting {
  typealias InstallScriptResult = Result<RuntimeInstallOutcome, RuntimeInstallError>

  nonisolated static let half = RuntimeInstallProgress.downloading(
    fraction: 0.5,
    completed: 1_880_000_000,
    total: 3_760_000_000
  )

  nonisolated static let results: [InstallScriptResult] = [
    .success(.installed), .success(.alreadyInstalled), .failure(.failed), .failure(.launchFailed),
    .failure(.cancelled),
  ]

  static func setupResult(_ result: InstallScriptResult) -> SetupInstallResult {
    switch result {
    case let .success(outcome): .finished(outcome)
    case let .failure(error): .failed(error)
    }
  }

  @Test("설치를 누르면 준비에서 시작해 받은 진행을 차례로 보인다")
  func installShowsProgress() async {
    let setup = await Self.notInstalledModel { fake, _ in fake.suspendInstalls() }
    let (model, fake, simulator) = (setup.model, setup.fake, setup.simulator)

    let install = await Self.startSuspendedInstall(model, fake)
    #expect(model.isInstallingRuntime)
    #expect(model.runtimeInstall?.progress == .preparing)
    #expect(model.canCancelRuntimeInstall)
    #expect(model.steps.map(\.progress) == [.done, .done, .done, .current])

    await fake.sendInstallProgress(Self.half)
    #expect(model.runtimeInstall?.progress == Self.half)
    await fake.sendInstallProgress(.installing)
    #expect(model.runtimeInstall?.progress == .installing)

    simulator.setRuntimeImages(RuntimeImage.samples)
    fake.resumeInstalls()
    await install.value()
    #expect(model.runtimeInstall == nil)
    #expect(model.lastInstallResult == .finished(.installed))
    #expect(model.runtimeState.isInstalled)
    #expect(Self.installCount(in: fake) == 1)
  }

  @Test("설치가 끝나면 결과와 관계없이 환경과 런타임을 다시 확인한다", arguments: results)
  func installRechecksForEveryResult(result: InstallScriptResult) async {
    let setup = await Self.notInstalledModel { fake, _ in
      fake.setInstallScript(progress: [.preparing], result: result)
    }
    let (model, fake, simulator) = (setup.model, setup.fake, setup.simulator)
    let checks = Self.checkCount(in: fake)
    let fetches = Self.fetchCount(in: simulator)
    simulator.setRuntimeImages(RuntimeImage.samples)

    await model.installRuntimeButtonTapped()

    #expect(Self.checkCount(in: fake) == checks + 1)
    #expect(Self.fetchCount(in: simulator) == fetches + 1)
    #expect(model.lastInstallResult == Self.setupResult(result))
    #expect(model.runtimeState.isInstalled)
    #expect(model.runtimeInstall == nil)
    #expect(!model.isVerifyingInstall)
    #expect(!model.isChecking)
  }

  @Test("취소를 누르면 설치를 멈추고 취소 결과를 남긴다")
  func cancelStopsInstall() async {
    let setup = await Self.notInstalledModel { fake, _ in fake.suspendInstalls() }
    let (model, fake) = (setup.model, setup.fake)
    let install = await Self.startSuspendedInstall(model, fake)

    model.cancelInstallButtonTapped()
    #expect(model.runtimeInstall?.isCancelling == true)
    #expect(!model.canCancelRuntimeInstall)

    await install.value()
    #expect(model.lastInstallResult == .failed(.cancelled))
    #expect(model.runtimeInstall == nil)
    #expect(fake.suspendedInstallCount == 0)
    #expect(model.runtimeState == .checked(.sample, .notInstalled))
    #expect(model.canInstallRuntime)
  }

  @Test("설치 단계에서는 취소할 수 없고 취소를 눌러도 멈추지 않는다")
  func cannotCancelWhileInstallingPhase() async {
    let setup = await Self.notInstalledModel { fake, _ in fake.suspendInstalls() }
    let (model, fake) = (setup.model, setup.fake)
    let install = await Self.startSuspendedInstall(model, fake)
    await fake.sendInstallProgress(.installing)

    #expect(!model.canCancelRuntimeInstall)
    model.cancelInstallButtonTapped()
    #expect(model.runtimeInstall?.isCancelling == false)
    for _ in 0 ..< 10 {
      await Task.yield()
    }
    #expect(fake.suspendedInstallCount == 1)
    #expect(!install.isFinished)

    fake.resumeInstalls()
    await install.value()
    #expect(model.lastInstallResult == .finished(.installed))
  }

  @Test("멈추는 중에는 취소를 다시 누를 수 없다")
  func cannotCancelTwice() async {
    let setup = await Self.notInstalledModel { fake, _ in fake.suspendInstalls() }
    let (model, fake) = (setup.model, setup.fake)
    let install = await Self.startSuspendedInstall(model, fake)

    model.cancelInstallButtonTapped()
    let afterFirst = model.runtimeInstall
    #expect(afterFirst?.isCancelling == true)
    #expect(afterFirst?.canCancel == false)
    #expect(!model.canCancelRuntimeInstall)
    model.cancelInstallButtonTapped()
    #expect(model.runtimeInstall == afterFirst)

    await install.value()
    #expect(model.lastInstallResult == .failed(.cancelled))
    #expect(Self.installCount(in: fake) == 1)
  }

  @Test("취소한 설치 뒤의 다시 확인은 취소되지 않는다")
  func recheckAfterCancelIsNotCancelled() async {
    let setup = await Self.notInstalledModel { fake, _ in fake.suspendInstalls() }
    let (model, fake) = (setup.model, setup.fake)
    let install = await Self.startSuspendedInstall(model, fake)
    let checks = Self.checkCount(in: fake)

    model.cancelInstallButtonTapped()
    await install.value()

    // Fake 는 취소된 Task 의 확인이면 .checkFailed 를 던진다.
    #expect(Self.checkCount(in: fake) == checks + 1)
    #expect(model.checkState == .checked(.ready(.sample)))
    #expect(model.runtimeState == .checked(.sample, .notInstalled))
  }

  @Test("다시 설치하면 지난 결과가 지워진다")
  func reinstallClearsLastResult() async {
    let setup = await Self.notInstalledModel { fake, _ in
      fake.setInstallScript(progress: [.preparing], result: .failure(.failed))
    }
    let (model, fake) = (setup.model, setup.fake)
    await model.installRuntimeButtonTapped()
    #expect(model.lastInstallResult == .failed(.failed))

    fake.setInstallScript(progress: [.preparing], result: .success(.installed))
    fake.suspendInstalls()
    let install = await Self.startSuspendedInstall(model, fake)
    #expect(model.lastInstallResult == nil)

    fake.resumeInstalls()
    await install.value()
    #expect(model.lastInstallResult == .finished(.installed))
  }

  @Test("설치가 끝났는데 기본 iOS 가 보이지 않으면 그 결과를 보인다")
  func installedButNotVisible() async {
    let setup = await Self.notInstalledModel()
    let model = setup.model

    await model.installRuntimeButtonTapped()

    #expect(model.lastInstallResult == .finished(.installed))
    #expect(model.runtimeState == .checked(.sample, .notInstalled))
    #expect(model.canInstallRuntime)
    #expect(
      SetupText.installResultMessage(for: model.lastInstallResult, runtime: model.runtimeState)
        == "설치가 끝났지만 iOS 시뮬레이터가 아직 보이지 않습니다. 잠시 뒤 다시 확인을 누르세요."
    )
  }

  @Test("설치가 끝나고 다시 확인하는 동안에는 결과 확인 중으로 보이고 결과 줄을 고르지 않는다")
  func verifyingAfterInstall() async {
    let setup = await Self.notInstalledModel { fake, _ in fake.suspendInstalls() }
    let (model, fake, simulator) = (setup.model, setup.fake, setup.simulator)
    let install = await Self.startSuspendedInstall(model, fake)
    #expect(!model.isVerifyingInstall)
    let checks = Self.checkCount(in: fake)
    fake.suspendChecks()

    fake.resumeInstalls()
    await Self.waitUntil { Self.checkCount(in: fake) == checks + 1 }

    #expect(model.isVerifyingInstall)
    #expect(model.runtimeInstall == nil)
    #expect(model.lastInstallResult == .finished(.installed))
    // 옛 런타임 상태는 그대로이지만 화면은 결과 확인 중이다.
    #expect(model.runtimeState == .checked(.sample, .notInstalled))
    #expect(!model.canInstallRuntime)
    #expect(!model.canRecheck)
    #expect(!model.canFinish)

    simulator.setRuntimeImages(RuntimeImage.samples)
    fake.resumeChecks()
    await install.value()
    #expect(!model.isVerifyingInstall)
    #expect(model.runtimeState.isInstalled)
    #expect(
      SetupText.installResultMessage(for: model.lastInstallResult, runtime: model.runtimeState)
        == "iOS 시뮬레이터를 설치했습니다."
    )
  }

  @Test("설치가 끝난 뒤 다시 확인이 실패하면 결과 확인 중을 내리고 확인 실패를 보인다")
  func verifyingEndsOnCheckFailure() async {
    let setup = await Self.notInstalledModel { fake, _ in fake.suspendInstalls() }
    let (model, fake) = (setup.model, setup.fake)
    let install = await Self.startSuspendedInstall(model, fake)
    fake.setCheckError(.checkFailed)

    fake.resumeInstalls()
    await install.value()

    #expect(!model.isVerifyingInstall)
    #expect(model.checkState == .failed(.checkFailed))
    #expect(model.runtimeState == .notChecked)
    #expect(model.steps.isEmpty)
    #expect(model.canRecheck)
  }

  @Test("다시 열면 지난 설치 결과가 지워진다")
  func reopenedClearsLastResult() async {
    let setup = await Self.notInstalledModel { fake, _ in
      fake.setInstallScript(progress: [.preparing], result: .failure(.cancelled))
    }
    let model = setup.model
    await model.installRuntimeButtonTapped()
    #expect(model.lastInstallResult == .failed(.cancelled))

    model.reopened()

    #expect(model.lastInstallResult == nil)
  }

  @Test("Xcode 가 없어져 설치하지 못하면 다시 확인해 Xcode 설치 단계를 보인다")
  func xcodeGoneDuringInstall() async {
    let setup = await Self.notInstalledModel { fake, _ in
      fake.setInstallScript(progress: [.preparing], result: .failure(.xcodeNotFound))
    }
    let (model, fake, simulator) = (setup.model, setup.fake, setup.simulator)
    let fetches = Self.fetchCount(in: simulator)
    fake.setStatus(.xcodeNotInstalled)

    await model.installRuntimeButtonTapped()

    #expect(model.lastInstallResult == .failed(.xcodeNotFound))
    #expect(model.checkState == .checked(.xcodeNotInstalled))
    #expect(model.runtimeState == .notChecked)
    #expect(model.steps.map(\.progress) == [.current, .pending, .pending, .pending])
    #expect(Self.fetchCount(in: simulator) == fetches)
  }
}

/// 설치 중·확인 중에 막는 동작: 설치·확인·기기 목록 이동이 겹치지 않는다.
@MainActor
struct SetupInstallGuardTests: SetupModelTesting {
  @Test("설치 중에는 설치를 다시 시작하지 않는다")
  func secondInstallIgnored() async {
    let setup = await Self.notInstalledModel { fake, _ in fake.suspendInstalls() }
    let (model, fake) = (setup.model, setup.fake)
    let install = await Self.startSuspendedInstall(model, fake)
    #expect(!model.canInstallRuntime)

    let second = Self.start { await model.installRuntimeButtonTapped() }
    await Self.waitUntil { second.isFinished }
    #expect(Self.installCount(in: fake) == 1)

    fake.resumeInstalls()
    await install.value()
  }

  @Test("설치 중에는 다시 확인·앱 활성화·화면 나타남이 확인하지 않는다")
  func noCheckWhileInstalling() async {
    let setup = await Self.notInstalledModel { fake, _ in fake.suspendInstalls() }
    let (model, fake, simulator) = (setup.model, setup.fake, setup.simulator)
    let install = await Self.startSuspendedInstall(model, fake)
    let checks = Self.checkCount(in: fake)
    let fetches = Self.fetchCount(in: simulator)
    #expect(!model.canRecheck)

    await model.recheckButtonTapped()
    await model.appBecameActive()
    await model.onAppear()

    #expect(Self.checkCount(in: fake) == checks)
    #expect(Self.fetchCount(in: simulator) == fetches)
    #expect(!model.isChecking)
    #expect(model.isInstallingRuntime)

    fake.resumeInstalls()
    await install.value()
    #expect(Self.checkCount(in: fake) == checks + 1)
    #expect(model.canRecheck)
  }

  @Test("설치 중에는 기기 목록 열기가 끝내지 않는다")
  func finishIgnoredWhileInstalling() async {
    let setup = await Self.notInstalledModel { fake, _ in fake.suspendInstalls() }
    let (model, fake) = (setup.model, setup.fake)
    let install = await Self.startSuspendedInstall(model, fake)

    #expect(!model.canFinish)
    model.doneButtonTapped()
    #expect(!model.isFinished)

    fake.resumeInstalls()
    await install.value()
    #expect(model.canFinish)
  }

  @Test("확인 중에는 설치를 시작하지 않는다")
  func noInstallWhileChecking() async {
    let setup = await Self.notInstalledModel()
    let (model, fake) = (setup.model, setup.fake)
    fake.suspendChecks()
    let checks = Self.checkCount(in: fake)
    let recheck = Self.start { await model.recheckButtonTapped() }
    await Self.waitUntil { Self.checkCount(in: fake) == checks + 1 }

    #expect(!model.canInstallRuntime)
    await model.installRuntimeButtonTapped()
    #expect(Self.installCount(in: fake) == 0)
    #expect(model.runtimeInstall == nil)

    fake.resumeChecks()
    await recheck.value()
    #expect(model.canInstallRuntime)
  }

  @Test("확인을 시작한 직후(확인 Task 가 돌기 전)에도 설치를 시작하지 않는다")
  func noInstallRightAfterCheckStarts() async {
    let setup = await Self.notInstalledModel()
    let (model, fake) = (setup.model, setup.fake)
    fake.suspendChecks()

    // 같은 우선순위의 MainActor 작업은 넣은 순서대로 돈다(실행기 구현에 기댄 전제):
    // 다시 확인 이벤트(확인 Task 를 만든다) → 상태 읽기 → 설치 이벤트 → 확인 Task 몸체.
    // 그래서 뒤의 두 작업은 다시 확인의 동기 부분만 돌고 확인 Task 몸체는 아직 돌지 않은 시점에 돈다.
    let recheck = Task { await model.recheckButtonTapped() }
    let canInstallThen = Task { model.canInstallRuntime }
    let install = Self.start { await model.installRuntimeButtonTapped() }

    #expect(await canInstallThen.value == false)
    // 회귀로 설치가 시작되면 설치 뒤 다시 확인이 멈춘 확인을 기다려 끝나지 않으므로, 설치 호출도 함께 본다.
    await Self.waitUntil { install.isFinished || Self.installCount(in: fake) > 0 }
    #expect(install.isFinished)
    #expect(Self.installCount(in: fake) == 0)
    #expect(model.runtimeInstall == nil)
    #expect(model.isChecking)

    fake.resumeChecks()
    await recheck.value
    await install.value()
    #expect(model.canInstallRuntime)
  }
}
