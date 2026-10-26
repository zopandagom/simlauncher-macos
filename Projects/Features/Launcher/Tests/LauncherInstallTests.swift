import AppBundleInterface
import AppBundleTesting
import Core
import DownloadTesting
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
import WorkspaceTesting
@testable import LauncherFeature

@MainActor
struct LauncherInstallTests: LauncherModelTesting {
  /// 사용자가 고른 경로. Fake 검사 결과의 `location`(`/tmp/SampleApp.app`)과 일부러 다르게 둔다.
  static let picked = URL(filePath: "/Users/tester/Downloads/My App.app", directoryHint: .isDirectory)
  static let sample = AppBundleInfo.sample

  // MARK: - 성공 흐름

  @Test("켜진 기기에 고르면 검사 → 앱 열기 → 설치 → 실행 → 다시 읽기 순서이고 켜지 않으며 알림이 없다")
  func installOnBootedDevice() async {
    let appBundle = AppBundleClientFake()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)

    await model.appFileSelected(Self.picked, for: SampleID.iPhoneOn)

    #expect(appBundle.calls == [.inspect(Self.picked)])
    #expect(simulator.calls == [
      .fetchInventory,
      .openSimulatorApp,
      .install(Self.sample.location, SampleID.iPhoneOn),
      .launch(Self.sample.bundleID, SampleID.iPhoneOn),
      .fetchInventory,
    ])
    #expect(model.notices.isEmpty)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("꺼진 기기면 검사 → 켜기 → 앱 열기 → 설치 → 실행 → 다시 읽기이고 끝나면 켜짐이다")
  func installOnShutdownDevice() async {
    let appBundle = AppBundleClientFake()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)

    await model.appFileSelected(Self.picked, for: SampleID.iPhoneOff)

    #expect(appBundle.calls == [.inspect(Self.picked)])
    #expect(simulator.calls == [
      .fetchInventory,
      .boot(SampleID.iPhoneOff),
      .openSimulatorApp,
      .install(Self.sample.location, SampleID.iPhoneOff),
      .launch(Self.sample.bundleID, SampleID.iPhoneOff),
      .fetchInventory,
    ])
    #expect(Self.device(SampleID.iPhoneOff, in: model)?.state == .booted)
    #expect(model.notices.isEmpty)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("검사·켜기·설치 단계마다 설치 중이고, 같은 기기의 켜기·끄기·두 번째 설치는 호출을 만들지 않으며, 끝나면 풀린다")
  func installingAtEveryStepBlocksSameDevice() async {
    let appBundle = AppBundleClientFake()
    appBundle.suspendInspections()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle) { simulator in
      simulator.suspendBoots()
      simulator.suspendInstalls()
    }
    let id = SampleID.iPhoneOff
    let install = Task { await model.appFileSelected(Self.picked, for: id) }

    await Self.waitUntil { appBundle.calls.count == 1 }
    await Self.expectInstallBlocks(id, model: model, simulator: simulator, appBundle: appBundle)
    appBundle.resumeInspections()

    await Self.waitUntil { simulator.calls.contains(.boot(id)) }
    await Self.expectInstallBlocks(id, model: model, simulator: simulator, appBundle: appBundle)
    simulator.resumeBoots()

    await Self.waitUntil { simulator.calls.contains(.install(Self.sample.location, id)) }
    await Self.expectInstallBlocks(id, model: model, simulator: simulator, appBundle: appBundle)
    simulator.resumeInstalls()

    await install.value
    #expect(model.activity.task(on: id) == nil)
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(Self.installCount(in: simulator) == 1)
  }

  // MARK: - 명령 전 거절

  @Test("검사가 실패하면 이유를 알리고 시뮬레이터를 부르지 않으며 다시 읽지 않는다", arguments: [
    AppBundleError.notLocalFile, .fileNotFound, .ipaFile, .notAppBundle, .macOSApp, .invalidBundle,
  ])
  func inspectFailure(error: AppBundleError) async {
    let appBundle = AppBundleClientFake()
    appBundle.setInspectError(error)
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)

    await model.appFileSelected(Self.picked, for: SampleID.iPhoneOff)

    #expect(model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOff), .bundle(error))])
    #expect(simulator.calls == [.fetchInventory])
    #expect(model.activity.task(on: SampleID.iPhoneOff) == nil)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("이 기기에 맞지 않는 빌드는 이유를 알리고 켜지 않는다", arguments: zip(
    [AppBundleInfo.deviceBuild, .x86Only, .requiring(OSVersion(major: 99))],
    [AppInstallProblem.notSimulatorBuild, .missingArchitecture(.arm64), .requiresNewerOS(OSVersion(major: 99))]
  ))
  func rejectedBuild(info: AppBundleInfo, problem: AppInstallProblem) async {
    let appBundle = AppBundleClientFake()
    appBundle.setInfo(info)
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)

    await model.appFileSelected(Self.picked, for: SampleID.iPhoneOff)

    #expect(model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOff), .rejected(problem))])
    #expect(simulator.calls == [.fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("이 Mac 이 Intel 이면 arm64 만 든 앱은 x86_64 가 없다고 거절한다")
  func intelHostRejectsArm64Only() async {
    let arm64Only = AppBundleInfo(
      bundleID: Self.sample.bundleID,
      displayName: Self.sample.displayName,
      version: Self.sample.version,
      build: Self.sample.build,
      platforms: [.iOSSimulator],
      architectures: [.arm64],
      minimumOSVersion: Self.sample.minimumOSVersion,
      location: Self.sample.location
    )
    let appBundle = AppBundleClientFake()
    appBundle.setInfo(arm64Only)
    appBundle.setHostArchitecture(.x86_64)
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)

    await model.appFileSelected(Self.picked, for: SampleID.iPhoneOn)

    let notice = LauncherNotice.installFailed(Self.label(SampleID.iPhoneOn), .rejected(.missingArchitecture(.x86_64)))
    #expect(model.notices.map(\.notice) == [notice])
    #expect(simulator.calls == [.fetchInventory])
  }

  @Test("쓸 수 없는·켜는 중·목록에 없는 기기와 목록을 읽기 전에는 아무것도 부르지 않는다")
  func blockedDevicesCallNothing() async {
    let appBundle = AppBundleClientFake()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)
    await model.appFileSelected(Self.picked, for: SampleID.unavailableIPhone)
    await model.appFileSelected(Self.picked, for: SampleID.watch)
    await model.appDropped([Self.picked], on: VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF"))
    simulator.setInventory(Self.inventory(SampleID.iPhoneOff, state: .booting))
    await model.refreshButtonTapped()
    await model.appFileSelected(Self.picked, for: SampleID.iPhoneOff)

    #expect(appBundle.calls.isEmpty)
    #expect(simulator.calls == [.fetchInventory, .fetchInventory])
    #expect(model.notices.isEmpty)

    let before = AppBundleClientFake()
    let beforeLoad = LauncherModel(
      simulator: SimulatorClientFake(inventory: .sample),
      appBundle: before,
      download: DownloadClientFake(),
      workspace: WorkspaceClientFake()
    )
    await beforeLoad.appFileSelected(Self.picked, for: SampleID.iPhoneOff)
    #expect(before.calls.isEmpty)
  }

  // MARK: - 명령 실패

  @Test("켜기가 실패하면 알리고 설치하지 않으며, 다시 읽고 진행 중을 푼다")
  func bootFailure() async {
    let (model, simulator) = await Self.loadedModel { simulator in
      simulator.setBootError(.commandFailed)
    }

    await model.appFileSelected(Self.picked, for: SampleID.iPhoneOff)

    #expect(model.notices.map(\.notice) == [.bootFailed(Self.label(SampleID.iPhoneOff), .commandFailed)])
    #expect(simulator.calls == [.fetchInventory, .boot(SampleID.iPhoneOff), .fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("Simulator 앱을 열지 못해도 알리고 설치·실행은 이어간다 (켜진 기기도 앱을 연다)", arguments: [
    SampleID.iPhoneOff, SampleID.iPhoneOn,
  ])
  func openAppFailureContinues(id: VirtualDevice.ID) async {
    let (model, simulator) = await Self.loadedModel { simulator in
      simulator.setOpenAppError(.simulatorAppNotFound)
    }

    await model.appFileSelected(Self.picked, for: id)

    #expect(model.notices.map(\.notice) == [.openAppFailed(Self.label(id), .simulatorAppNotFound)])
    #expect(simulator.calls.contains(.openSimulatorApp))
    #expect(simulator.calls.suffix(3) == [
      .install(Self.sample.location, id), .launch(Self.sample.bundleID, id), .fetchInventory,
    ])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("설치가 실패하면 알리고 실행하지 않으며, 다시 읽고 진행 중을 푼다")
  func installFailure() async {
    let (model, simulator) = await Self.loadedModel { simulator in
      simulator.setInstallError(.appIncompatible)
    }

    await model.appFileSelected(Self.picked, for: SampleID.iPhoneOn)

    #expect(
      model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOn), .simulator(.appIncompatible))]
    )
    #expect(!simulator.calls.contains(.launch(Self.sample.bundleID, SampleID.iPhoneOn)))
    #expect(simulator.calls.last == .fetchInventory)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("실행이 실패하면 알리고 다시 읽으며 진행 중을 푼다")
  func launchFailure() async {
    let (model, simulator) = await Self.loadedModel { simulator in
      simulator.setLaunchError(.appLaunchFailed)
    }

    await model.appFileSelected(Self.picked, for: SampleID.iPhoneOn)

    #expect(model.notices.map(\.notice) == [.launchFailed(Self.label(SampleID.iPhoneOn), .appLaunchFailed)])
    #expect(simulator.calls.suffix(2) == [.launch(Self.sample.bundleID, SampleID.iPhoneOn), .fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  // MARK: - 드롭

  @Test("둘 이상 드롭하면(zip 포함) 이유를 알리고 검사·풀기를 하지 않으며, 빈 드롭은 아무것도 하지 않는다", arguments: [
    ["My App.app", "Other.app"], ["A.zip", "B.zip"], ["A.zip", "My App.app"],
  ])
  func dropCountRules(names: [String]) async {
    let appBundle = AppBundleClientFake()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)
    let items = names.map { URL(filePath: "/Users/tester/Downloads").appending(path: $0) }

    await model.appDropped([], on: SampleID.iPhoneOn)
    #expect(model.notices.isEmpty)

    await model.appDropped(items, on: SampleID.iPhoneOn)
    #expect(model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOn), .multipleItems)])
    #expect(appBundle.calls.isEmpty)
    #expect(simulator.calls == [.fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("하나를 드롭하면 고른 경우와 같은 흐름이다")
  func singleDropInstalls() async {
    let appBundle = AppBundleClientFake()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)

    await model.appDropped([Self.picked], on: SampleID.iPhoneOn)

    #expect(appBundle.calls == [.inspect(Self.picked)])
    #expect(simulator.calls == [
      .fetchInventory,
      .openSimulatorApp,
      .install(Self.sample.location, SampleID.iPhoneOn),
      .launch(Self.sample.bundleID, SampleID.iPhoneOn),
      .fetchInventory,
    ])
    #expect(model.notices.isEmpty)
  }

  @Test("실패 뒤 목록에서 사라진 기기도 누른 시점의 이름으로 알린다")
  func noticeKeepsNameOfRemovedDevice() async {
    let (model, simulator) = await Self.loadedModel()
    // Model 의 목록에는 남아 있지만 시뮬레이터에서는 이미 사라져 설치가 `.deviceNotFound` 로 실패한다.
    simulator.setInventory(Self.inventory(removing: SampleID.iPhoneOn))

    await model.appFileSelected(Self.picked, for: SampleID.iPhoneOn)

    let label = LauncherNotice.Device(name: "iPhone 17 Pro", runtimeName: "iOS 27.0")
    #expect(model.notices.map(\.notice) == [.installFailed(label, .simulator(.deviceNotFound))])
    #expect(Self.device(SampleID.iPhoneOn, in: model) == nil)
  }
}

extension LauncherInstallTests {
  /// 설치 중인 기기: 진행 중으로 보이고, 같은 기기의 켜기·끄기·두 번째 설치가 호출을 만들지 않는다.
  /// 회귀가 있으면 시도가 멈춘 Fake 에 걸릴 수 있어 직접 await 하지 않고 띄운 뒤 끝남이나 호출 증가를 기다린다.
  static func expectInstallBlocks(
    _ id: VirtualDevice.ID,
    model: LauncherModel,
    simulator: SimulatorClientFake,
    appBundle: AppBundleClientFake,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    #expect(model.activity.task(on: id) == .installApp, sourceLocation: sourceLocation)
    #expect(model.busyDeviceIDs.contains(id), sourceLocation: sourceLocation)
    let simulatorCalls = simulator.calls.count
    let inspections = appBundle.calls.count
    let attempts = Self.start {
      await model.bootButtonTapped(id)
      await model.shutdownButtonTapped(id)
      await model.appFileSelected(Self.picked, for: id)
    }
    await Self.waitUntil(
      { attempts.isFinished || simulator.calls.count > simulatorCalls || appBundle.calls.count > inspections },
      sourceLocation: sourceLocation
    )
    #expect(simulator.calls.count == simulatorCalls, sourceLocation: sourceLocation)
    #expect(appBundle.calls.count == inspections, sourceLocation: sourceLocation)
  }

  static func installCount(in simulator: SimulatorClientFake) -> Int {
    simulator.calls.filter {
      if case .install = $0 {
        true
      } else {
        false
      }
    }.count
  }
}
