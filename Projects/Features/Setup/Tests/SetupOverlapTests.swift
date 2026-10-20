import Core
import DevEnvironmentInterface
import DevEnvironmentTesting
import Testing
@testable import SetupFeature

@MainActor
struct SetupOverlapTests: SetupModelTesting {
  @Test("확인 중에 들어온 요청은 겹치지 않고, 끝난 뒤 한 번만 더 확인해 마지막 결과를 보인다")
  func requestsDuringCheckCoalesce() async {
    let (model, fake) = await Self.checkedModel(.xcodeNotInstalled)
    fake.suspendChecks()

    let first = Self.start { await model.recheckButtonTapped() }
    await Self.waitUntil { Self.checkCount(in: fake) == 2 }
    let joined = [
      Self.start { await model.recheckButtonTapped() },
      Self.start { await model.recheckButtonTapped() },
      Self.start { await model.recheckButtonTapped() },
      Self.start { await model.appBecameActive() },
    ]
    // 합류한 요청이 모두 진행 중인 확인을 기다리기 시작할 때까지 차례를 넘긴다.
    for _ in 0 ..< 10 {
      await Task.yield()
    }
    #expect(Self.checkCount(in: fake) == 2)
    // 진행 중인 확인은 이전 상태로 끝내고, 재확인이 시작된 뒤 상태를 바꿔 두 결과를 구분한다.
    fake.resumeChecks()
    fake.suspendChecks()
    await Self.waitUntil { Self.checkCount(in: fake) == 3 }
    #expect(model.checkState == .checked(.xcodeNotInstalled))
    fake.setStatus(.licenseNotAccepted(.sample))

    fake.resumeChecks()
    await first.value()
    for task in joined {
      await task.value()
    }

    #expect(Self.checkCount(in: fake) == 3)
    #expect(model.checkState == .checked(.licenseNotAccepted(.sample)))
    #expect(!model.isChecking)
  }

  @Test("첫 확인 중 들어온 재확인이 준비됨으로 끝나면 첫 판정으로 보고 자동으로 끝난다")
  func firstCheckLoopResultDecidesAutoFinish() async {
    let fake = DevEnvironmentClientFake(status: .xcodeNotInstalled)
    fake.suspendChecks()
    let model = SetupModel(devEnvironment: fake)

    let appear = Self.start { await model.onAppear() }
    await Self.waitUntil { Self.checkCount(in: fake) == 1 }
    let active = Self.start { await model.appBecameActive() }
    for _ in 0 ..< 10 {
      await Task.yield()
    }
    // 첫 확인은 미준비로 끝내고, 재확인이 시작된 뒤 준비됨으로 바꿔 루프의 마지막 결과로 판단하는지 본다.
    fake.resumeChecks()
    fake.suspendChecks()
    await Self.waitUntil { Self.checkCount(in: fake) == 2 }
    #expect(model.checkState == .checked(.xcodeNotInstalled))
    #expect(!model.isFinished)
    fake.setStatus(.ready(.sample))

    fake.resumeChecks()
    await appear.value()
    await active.value()

    #expect(Self.checkCount(in: fake) == 2)
    #expect(model.isFinished)
    #expect(model.checkState == .checked(.ready(.sample)))
  }

  @Test("여는 중에 다시 누르면 한 번만 열고, 끝나면 여는 중 표시가 풀린다")
  func secondOpenWhileOpeningIsIgnored() async {
    let (model, fake) = await Self.checkedModel(.licenseNotAccepted(.sample))
    fake.suspendOpens()

    let first = Self.start { await model.openXcodeButtonTapped() }
    await Self.waitUntil { fake.calls.contains(.openXcode) }
    #expect(model.isOpening)
    let second = Self.start { await model.openXcodeButtonTapped() }
    let appStore = Self.start { await model.openAppStoreButtonTapped() }
    await Self.waitUntil { second.isFinished && appStore.isFinished }

    #expect(fake.calls == [.checkEnvironment, .openXcode])

    fake.resumeOpens()
    await first.value()
    #expect(!model.isOpening)
  }

  @Test("확인 중에도 Xcode 열기를 누를 수 있다")
  func openWhileChecking() async {
    let (model, fake) = await Self.checkedModel(.licenseNotAccepted(.sample))
    fake.suspendChecks()

    let recheck = Self.start { await model.recheckButtonTapped() }
    await Self.waitUntil { Self.checkCount(in: fake) == 2 }

    await model.openXcodeButtonTapped()
    #expect(fake.calls.last == .openXcode)
    #expect(model.isChecking)

    fake.resumeChecks()
    await recheck.value()
  }
}
