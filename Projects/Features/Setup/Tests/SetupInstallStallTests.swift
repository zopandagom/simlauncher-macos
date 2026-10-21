import Core
import DevEnvironmentInterface
import DevEnvironmentTesting
import Testing
@testable import SetupFeature

/// 진행 알림 없이 60초가 지났을 때의 연결 확인 안내. 시계는 `TestSleeper` 로 대신한다 (실제로 기다리지 않는다).
@MainActor
struct SetupInstallStallTests: SetupModelTesting {
  nonisolated static let half = RuntimeInstallProgress.downloading(fraction: 0.5)
  nonisolated static let later = RuntimeInstallProgress.downloading(fraction: 0.6)

  /// 설치를 멈춘 채 띄우고, 첫 진행(.preparing)으로 다시 건 시계가 걸릴 때까지 기다린다.
  static func stalledReadyInstall(_ sleeper: TestSleeper) async -> (SetupFixture, TrackedTask) {
    let setup = await Self.notInstalledModel(sleeper: sleeper) { fake, _ in fake.suspendInstalls() }
    let install = await Self.startSuspendedInstall(setup.model, setup.fake)
    await Self.waitUntil { sleeper.pendingDurations == [.seconds(60)] }
    return (setup, install)
  }

  /// 시계를 울리고 안내가 붙을 때까지 기다린다.
  static func fireAndWaitForStall(_ sleeper: TestSleeper, _ model: SetupModel) async {
    sleeper.fireAll()
    await waitUntil { model.runtimeInstall?.isStalled == true }
  }

  @Test("진행 없이 60초가 지나면 연결 확인 안내를 보이고 취소는 그대로 할 수 있다")
  func stallShowsNotice() async {
    let sleeper = TestSleeper()
    let (setup, install) = await Self.stalledReadyInstall(sleeper)
    let model = setup.model
    #expect(sleeper.pendingDurations == [.seconds(60)])
    #expect(model.runtimeInstall?.isStalled == false)

    await Self.fireAndWaitForStall(sleeper, model)

    #expect(model.runtimeInstall?.progress == .preparing)
    #expect(model.canCancelRuntimeInstall)
    model.cancelInstallButtonTapped()
    #expect(model.runtimeInstall?.isStalled == false)
    await install.value()
    #expect(model.lastInstallResult == .failed(.cancelled))
  }

  @Test("새 진행이 오면 안내가 사라지고 60초를 다시 잰다")
  func progressClearsStall() async {
    let sleeper = TestSleeper()
    let (setup, install) = await Self.stalledReadyInstall(sleeper)
    let (model, fake) = (setup.model, setup.fake)
    await Self.fireAndWaitForStall(sleeper, model)
    #expect(sleeper.pendingDurations.isEmpty)

    await fake.sendInstallProgress(Self.half)

    #expect(model.runtimeInstall?.isStalled == false)
    await Self.waitUntil { sleeper.pendingDurations == [.seconds(60)] }

    // 진행이 이어지면 앞 시계는 취소되고 새 시계 하나만 남는다.
    await fake.sendInstallProgress(Self.later)
    await Self.waitUntil { sleeper.pendingDurations == [.seconds(60)] }
    await Self.fireAndWaitForStall(sleeper, model)
    #expect(model.runtimeInstall?.progress == Self.later)

    fake.resumeInstalls()
    await install.value()
  }

  @Test("설치 단계로 넘어가면 시계를 멈추고 안내를 보이지 않는다")
  func installingPhaseStopsTimer() async {
    let sleeper = TestSleeper()
    let (setup, install) = await Self.stalledReadyInstall(sleeper)
    let (model, fake) = (setup.model, setup.fake)
    // 안내가 붙은 뒤 진행이 와서 시계를 다시 건 상태에서 설치 단계로 넘어간다.
    await Self.fireAndWaitForStall(sleeper, model)
    await fake.sendInstallProgress(Self.half)
    await Self.waitUntil { sleeper.pendingDurations == [.seconds(60)] }

    await fake.sendInstallProgress(.installing)

    #expect(sleeper.pendingDurations.isEmpty)
    sleeper.fireAll()
    for _ in 0 ..< 10 {
      await Task.yield()
    }
    #expect(model.runtimeInstall?.isStalled == false)
    #expect(model.runtimeInstall?.progress == .installing)

    fake.resumeInstalls()
    await install.value()
  }

  @Test("설치가 끝나거나 취소하면 시계를 멈춘다")
  func finishOrCancelStopsTimer() async {
    let sleeper = TestSleeper()
    let (setup, first) = await Self.stalledReadyInstall(sleeper)
    let (model, fake) = (setup.model, setup.fake)

    model.cancelInstallButtonTapped()
    #expect(sleeper.pendingDurations.isEmpty)
    await first.value()
    #expect(model.lastInstallResult == .failed(.cancelled))

    let second = await Self.startSuspendedInstall(model, fake)
    await Self.waitUntil { sleeper.pendingDurations == [.seconds(60)] }
    fake.resumeInstalls()
    await second.value()
    #expect(sleeper.pendingDurations.isEmpty)
    #expect(model.lastInstallResult == .finished(.installed))
  }

  @Test("새 진행으로 취소된 시계가 늦게 울려도 안내가 붙지 않는다")
  func cancelledTimerFiringLateIsIgnored() async {
    let sleeper = TestSleeper(ignoresCancellation: true)
    let setup = await Self.notInstalledModel(sleeper: sleeper) { fake, _ in
      // 첫 진행을 테스트가 보내, 설치 시작 때 건 시계 T0 이 먼저 걸리게 한다.
      fake.setInstallScript(progress: [], result: .success(.installed))
      fake.suspendInstalls()
    }
    let (model, fake) = (setup.model, setup.fake)
    let install = await Self.startSuspendedInstall(model, fake)
    await Self.waitUntil { sleeper.pendingDurations.count == 1 }

    // 진행 P1 이 T0 을 취소하고 T1 을 건다. T0 의 sleep 은 취소를 무시해 그대로 남는다.
    await fake.sendInstallProgress(.preparing)
    await Self.waitUntil { sleeper.pendingDurations.count == 2 }

    // 취소된 T0 만 정상으로 깨운다 (잠이 끝난 뒤 취소가 온 순서).
    sleeper.fireOldest()
    // T0 의 Task 가 끝날 때까지 기다린 뒤 안내가 붙지 않았는지 본다.
    await Self.waitUntil { model.stallTimerEndCount == 1 }
    #expect(model.runtimeInstall?.isStalled == false)
    #expect(sleeper.pendingDurations.count == 1)

    // 남은 T1 은 안내를 붙인다.
    sleeper.fireOldest()
    await Self.waitUntil { model.runtimeInstall?.isStalled == true }

    fake.resumeInstalls()
    await install.value()
    sleeper.fireAll()
  }
}
