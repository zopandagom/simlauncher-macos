import Core
import DevEnvironmentInterface
import DevEnvironmentTesting
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import SetupFeature

/// Xcode 준비됨일 때의 기본 iOS 런타임 확인.
@MainActor
struct SetupRuntimeCheckTests: SetupModelTesting {
  nonisolated static let notReadyStatuses: [DevEnvironmentStatus] = [
    .xcodeNotInstalled, .commandLineToolsOnly, .licenseNotAccepted(.sample), .firstLaunchRequired(.sample),
  ]

  /// 기본 iOS 27.1 과 같은 버전·build 의 이미지 (상태만 바꿔 쓴다).
  nonisolated static func defaultImage(_ state: RuntimeImage.State) -> RuntimeImage {
    let image = SampleRuntimeImage.iOS27Point1
    return RuntimeImage(
      id: image.id,
      runtimeID: image.runtimeID,
      platform: image.platform,
      version: image.version,
      build: image.build,
      state: state,
      sizeBytes: image.sizeBytes
    )
  }

  @Test("Xcode 가 준비되면 기본 iOS 와 런타임 이미지로 설치 여부를 보인다")
  func readyChecksRuntime() async {
    let setup = await Self.runtimeModel()
    let (model, fake, simulator) = (setup.model, setup.fake, setup.simulator)

    #expect(model.runtimeState == .checked(.sample, .installed(SampleRuntimeImage.iOS27Point1)))
    #expect(model.runtimeState.isInstalled)
    #expect(model.steps.map(\.progress) == [.done, .done, .done, .done])
    #expect(fake.calls == [.checkEnvironment, .defaultIOSRuntime])
    #expect(simulator.calls == [.fetchRuntimeImages])
    #expect(!model.canInstallRuntime)
  }

  @Test("기본 iOS 가 없으면 iOS 설치 단계가 지금 할 단계이고 설치할 수 있다")
  func notInstalledCanInstall() async {
    let setup = await Self.notInstalledModel()
    let model = setup.model

    #expect(model.runtimeState == .checked(.sample, .notInstalled))
    #expect(model.steps.map(\.progress) == [.done, .done, .done, .current])
    #expect(model.steps.last?.kind == .installRuntime)
    #expect(model.canInstallRuntime)
    #expect(!model.isInstallingRuntime)
  }

  @Test(
    "기본 iOS 이미지가 준비 중이거나 쓸 수 없으면 그 상태를 보이고 설치할 수 없다",
    arguments: [RuntimeImage.State.preparing, .unusable]
  )
  func preparingOrUnusable(state: RuntimeImage.State) async {
    let image = Self.defaultImage(state)
    let setup = await Self.runtimeModel(images: [image])
    let model = setup.model

    let expected: DefaultIOSRuntimeStatus = state == .preparing ? .preparing(image) : .unusable(image)
    #expect(model.runtimeState == .checked(.sample, expected))
    #expect(model.steps.map(\.progress) == [.done, .done, .done, .current])
    #expect(!model.canInstallRuntime)
  }

  @Test("Xcode 가 준비되지 않았으면 기본 iOS 와 런타임 목록을 읽지 않는다", arguments: notReadyStatuses)
  func notReadySkipsRuntime(status: DevEnvironmentStatus) async {
    let setup = await Self.runtimeModel(status)
    let (model, fake, simulator) = (setup.model, setup.fake, setup.simulator)

    #expect(model.runtimeState == .notChecked)
    #expect(!fake.calls.contains(.defaultIOSRuntime))
    #expect(simulator.calls.isEmpty)
    #expect(!model.canInstallRuntime)
  }

  @Test("기본 iOS 버전을 읽지 못하면 이미지를 읽지 않고 그 상태를 보인다")
  func defaultRuntimeUnknown() async {
    let setup = await Self.runtimeModel { fake, _ in fake.setDefaultIOSRuntime(nil) }
    let (model, fake, simulator) = (setup.model, setup.fake, setup.simulator)

    #expect(model.runtimeState == .defaultRuntimeUnknown)
    #expect(fake.calls == [.checkEnvironment, .defaultIOSRuntime])
    #expect(simulator.calls.isEmpty)
    #expect(model.steps.map(\.progress) == [.done, .done, .done, .current])
    #expect(!model.canInstallRuntime)
  }

  @Test("런타임 목록을 읽지 못하면 실패를 보이고 설치할 수 없다")
  func runtimeListFails() async {
    let setup = await Self.runtimeModel { _, simulator in simulator.setRuntimeImagesError(.commandFailed) }
    let model = setup.model

    #expect(model.runtimeState == .failed(.commandFailed))
    #expect(model.checkState == .checked(.ready(.sample)))
    #expect(!model.canInstallRuntime)
  }

  @Test("첫 판정이 준비됨이면 기본 iOS 가 없어도 자동으로 끝난다")
  func firstReadyFinishesWithoutRuntime() async {
    let setup = await Self.runtimeModel(images: [])
    let model = setup.model

    #expect(model.runtimeState == .checked(.sample, .notInstalled))
    #expect(model.isFinished)
  }

  @Test("기본 iOS 가 없어도 기기 목록 열기를 누를 수 있다")
  func finishWithoutRuntime() async {
    let setup = await Self.notInstalledModel()
    let model = setup.model
    #expect(!model.isFinished)
    #expect(model.canFinish)

    model.doneButtonTapped()

    #expect(model.isFinished)
  }

  @Test("다시 확인하면 런타임 상태도 다시 읽는다")
  func recheckRereadsRuntime() async {
    let setup = await Self.notInstalledModel()
    let (model, fake, simulator) = (setup.model, setup.fake, setup.simulator)
    simulator.setRuntimeImages(RuntimeImage.samples)

    await model.recheckButtonTapped()

    #expect(model.runtimeState == .checked(.sample, .installed(SampleRuntimeImage.iOS27Point1)))
    #expect(Self.fetchCount(in: simulator) == 2)
    #expect(fake.calls.filter { $0 == .defaultIOSRuntime }.count == 2)

    // Xcode 가 준비되지 않게 바뀌면 런타임 상태는 확인 전으로 돌아간다.
    fake.setStatus(.licenseNotAccepted(.sample))
    await model.appBecameActive()
    #expect(model.runtimeState == .notChecked)
    #expect(Self.fetchCount(in: simulator) == 2)
  }
}
