import Core
import DevEnvironmentInterface
import DevEnvironmentTesting
import Testing
@testable import SetupFeature

/// App 의 종료 요청 처리: 할 일 고르기, 준비·내려받기 중이면 설치를 멈추고 설치 단계면 멈추지 않은 채 끝나기를 기다리기.
@MainActor
struct SetupTerminationTests: SetupModelTesting {
  @Test("종료 요청 때 할 일은 설치 단계에 따라 다르다")
  func terminationActionByPhase() async {
    let setup = await Self.notInstalledModel { fake, _ in fake.suspendInstalls() }
    let (model, fake) = (setup.model, setup.fake)
    #expect(model.terminationAction == .terminateNow)

    let install = await Self.startSuspendedInstall(model, fake)
    #expect(model.runtimeInstall?.progress.phase == .preparing)
    #expect(model.terminationAction == .confirmThenCancel)
    await fake.sendInstallProgress(.downloading(fraction: 0.5))
    #expect(model.terminationAction == .confirmThenCancel)
    await fake.sendInstallProgress(.installing)
    #expect(model.terminationAction == .waitForInstall)
    fake.resumeInstalls()
    await install.value()
    #expect(model.terminationAction == .terminateNow)

    fake.suspendInstalls()
    let cancelled = await Self.startSuspendedInstall(model, fake)
    model.cancelInstallButtonTapped()
    #expect(model.terminationAction == .waitForInstall)
    await cancelled.value()
    #expect(model.terminationAction == .terminateNow)
  }

  @Test("종료 요청은 진행 중인 설치를 멈추고 끝날 때까지 기다리며 다시 확인하지 않는다")
  func terminationCancelsAndWaits() async {
    let setup = await Self.notInstalledModel { fake, _ in fake.suspendInstalls() }
    let (model, fake) = (setup.model, setup.fake)
    let install = await Self.startSuspendedInstall(model, fake)
    await fake.sendInstallProgress(.downloading(fraction: 0.5))
    let checks = Self.checkCount(in: fake)

    // 같은 우선순위의 MainActor 작업은 넣은 순서대로 돈다(실행기 구현에 기댄 전제):
    // 종료 요청의 동기 부분(멈추기 시작·종료 표시) 다음, 설치가 끝나기 전에 상태를 읽는다.
    let termination = Task { await model.appTerminationRequested() }
    let during = Task { (model.runtimeInstall, model.terminationAction) }
    let (installDuring, actionDuring) = await during.value
    #expect(installDuring?.isCancelling == true)
    #expect(installDuring?.endsWithTermination == true)
    #expect(actionDuring == .waitForInstall)

    // 회귀로 멈추지 않으면 설치가 끝나지 않아 기다림이 끝나지 않으므로, 제한 시간 안에 끝나는지 보고 실패면 재개해 정리한다.
    let finished = TrackedTask { await termination.value }
    await Self.waitUntil { finished.isFinished }
    fake.resumeInstalls()
    await finished.value()
    #expect(model.runtimeInstall == nil)
    #expect(model.lastInstallResult == .failed(.cancelled))
    #expect(fake.suspendedInstallCount == 0)
    #expect(!model.isVerifyingInstall)
    await install.value()
    #expect(Self.checkCount(in: fake) == checks)
    #expect(!model.isChecking)
  }

  @Test("설치 단계의 종료 요청은 멈추지 않고 설치가 끝날 때까지 기다린다")
  func terminationWaitsDuringInstallingPhase() async {
    let setup = await Self.notInstalledModel { fake, _ in fake.suspendInstalls() }
    let (model, fake) = (setup.model, setup.fake)
    let install = await Self.startSuspendedInstall(model, fake)
    await fake.sendInstallProgress(.installing)
    let checks = Self.checkCount(in: fake)

    let termination = Self.start { await model.appTerminationRequested() }
    await Self.waitUntil { model.runtimeInstall?.endsWithTermination == true }
    #expect(model.runtimeInstall?.isCancelling == false)
    for _ in 0 ..< 10 {
      await Task.yield()
    }
    #expect(!termination.isFinished)
    #expect(fake.suspendedInstallCount == 1)

    fake.resumeInstalls()
    await termination.value()
    #expect(model.lastInstallResult == .finished(.installed))
    #expect(model.runtimeInstall == nil)
    await install.value()
    #expect(Self.checkCount(in: fake) == checks)
  }

  @Test("설치 중이 아니면 종료 요청은 바로 돌아온다")
  func terminationWithoutInstallReturns() async {
    let setup = await Self.notInstalledModel()
    let (model, fake, simulator) = (setup.model, setup.fake, setup.simulator)
    let calls = fake.calls
    let simulatorCalls = simulator.calls

    await model.appTerminationRequested()

    #expect(fake.calls == calls)
    #expect(simulator.calls == simulatorCalls)
    #expect(model.runtimeInstall == nil)
    #expect(model.lastInstallResult == nil)
  }

  @Test("종료 대기 중에는 설치를 시작할 수 없다")
  func noInstallAfterTermination() async {
    let setup = await Self.notInstalledModel()
    let (model, fake) = (setup.model, setup.fake)
    #expect(model.canInstallRuntime)

    await model.appTerminationRequested()

    #expect(!model.canInstallRuntime)
    await model.installRuntimeButtonTapped()
    #expect(Self.installCount(in: fake) == 0)
    #expect(model.runtimeInstall == nil)
    // 확인도 시작하지 않는다.
    let checks = Self.checkCount(in: fake)
    await model.recheckButtonTapped()
    #expect(Self.checkCount(in: fake) == checks)
  }
}
