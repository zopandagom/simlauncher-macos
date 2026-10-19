import AppBundleTesting
import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

@MainActor
struct LauncherInstallOverlapTests: LauncherModelTesting {
  static let picked = LauncherInstallTests.picked
  static let sample = LauncherInstallTests.sample

  @Test("설치 중 같은 기기에 다시 고르거나 드롭해도 한 번만 검사한다")
  func secondInstallOnSameDeviceIsIgnored() async {
    let appBundle = AppBundleClientFake()
    appBundle.suspendInspections()
    let (model, _) = await Self.loadedModel(appBundle: appBundle)
    let install = Task { await model.appFileSelected(Self.picked, for: SampleID.iPhoneOn) }
    await Self.waitUntil { appBundle.calls.count == 1 }

    let again = Self.start {
      await model.appFileSelected(Self.picked, for: SampleID.iPhoneOn)
      await model.appDropped([Self.picked], on: SampleID.iPhoneOn)
    }
    await Self.waitUntil { again.isFinished || appBundle.calls.count > 1 }
    #expect(appBundle.calls.count == 1)

    appBundle.resumeInspections()
    await install.value
    await again.value()
    #expect(appBundle.calls.count == 1)
  }

  @Test("다른 두 기기에 함께 설치하면 둘 다 진행 중이 되고, 둘 다 끝난다")
  func installOnTwoDevicesConcurrently() async {
    let (model, simulator) = await Self.loadedModel { simulator in simulator.suspendInstalls() }
    let phone = Task { await model.appFileSelected(Self.picked, for: SampleID.iPhoneOn) }
    let pad = Task { await model.appFileSelected(Self.picked, for: SampleID.iPadOff) }
    await Self.waitUntil {
      simulator.calls.contains(.install(Self.sample.location, SampleID.iPhoneOn))
        && simulator.calls.contains(.install(Self.sample.location, SampleID.iPadOff))
    }
    #expect(model.activity.tasks == [SampleID.iPhoneOn: .installApp, SampleID.iPadOff: .installApp])

    simulator.resumeInstalls()
    await phone.value
    await pad.value
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(LauncherInstallTests.installCount(in: simulator) == 2)
    #expect(model.notices.isEmpty)
  }

  @Test("설치 중인 기기는 켜기·삭제·초기화 확인을 받지 않는다")
  func installingDeviceBlocksOtherActions() async {
    let appBundle = AppBundleClientFake()
    appBundle.suspendInspections()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)
    let id = SampleID.iPhoneOff
    let install = Task { await model.appFileSelected(Self.picked, for: id) }
    await Self.waitUntil { appBundle.calls.count == 1 }

    await model.bootButtonTapped(id)
    model.deleteButtonTapped(id)
    #expect(model.pendingConfirmation == nil)
    model.eraseButtonTapped(id)
    #expect(model.pendingConfirmation == nil)
    for action in [DeviceConfirmation.Action.delete, .erase] {
      await model.confirmationConfirmed(DeviceConfirmation(action: action, deviceID: id, device: Self.label(id)))
    }
    #expect(simulator.calls == [.fetchInventory])
    #expect(model.notices.isEmpty)

    appBundle.resumeInspections()
    await install.value
  }

  @Test("설치 중 새로 고쳐도 설치가 이어지고, 끝나면 상태가 반영된다")
  func refreshDuringInstall() async {
    let (model, simulator) = await Self.loadedModel { simulator in simulator.suspendInstalls() }
    let id = SampleID.iPhoneOff
    let install = Task { await model.appFileSelected(Self.picked, for: id) }
    await Self.waitUntil { simulator.calls.contains(.install(Self.sample.location, id)) }

    await model.refreshButtonTapped()
    #expect(Self.device(id, in: model)?.state == .booted)
    #expect(model.activity.task(on: id) == .installApp)

    simulator.resumeInstalls()
    await install.value
    #expect(simulator.calls.suffix(2) == [.launch(Self.sample.bundleID, id), .fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.notices.isEmpty)
  }

  @Test("검사하는 동안 기기가 목록에서 사라지면 찾을 수 없다고 알리고 명령을 실행하지 않는다")
  func deviceRemovedDuringInspection() async {
    let appBundle = AppBundleClientFake()
    appBundle.suspendInspections()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)
    let id = SampleID.iPhoneOff
    let install = Task { await model.appFileSelected(Self.picked, for: id) }
    await Self.waitUntil { appBundle.calls.count == 1 }
    simulator.setInventory(Self.inventory(removing: id))
    await model.refreshButtonTapped()

    appBundle.resumeInspections()
    await install.value

    #expect(model.notices.map(\.notice) == [.installFailed(Self.label(id), .simulator(.deviceNotFound))])
    #expect(simulator.calls == [.fetchInventory, .fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("검사하는 동안 기기가 켜는 중이 되면 상태가 바뀌는 중이라고 알린다")
  func deviceBootingDuringInspection() async {
    let appBundle = AppBundleClientFake()
    appBundle.suspendInspections()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)
    let id = SampleID.iPhoneOff
    let install = Task { await model.appFileSelected(Self.picked, for: id) }
    await Self.waitUntil { appBundle.calls.count == 1 }
    simulator.setInventory(Self.inventory(id, state: .booting))
    await model.refreshButtonTapped()

    appBundle.resumeInspections()
    await install.value

    #expect(model.notices.map(\.notice) == [.installFailed(Self.label(id), .deviceNotReady(.stateChanging))])
    #expect(simulator.calls == [.fetchInventory, .fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("검사하는 동안 기기가 밖에서 켜지면 켜지 않고 앱을 열어 설치한다")
  func deviceBootedDuringInspection() async {
    let appBundle = AppBundleClientFake()
    appBundle.suspendInspections()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)
    let id = SampleID.iPhoneOff
    let install = Task { await model.appFileSelected(Self.picked, for: id) }
    await Self.waitUntil { appBundle.calls.count == 1 }
    simulator.setInventory(Self.inventory(id, state: .booted))
    await model.refreshButtonTapped()

    appBundle.resumeInspections()
    await install.value

    #expect(simulator.calls == [
      .fetchInventory,
      .fetchInventory,
      .openSimulatorApp,
      .install(Self.sample.location, id),
      .launch(Self.sample.bundleID, id),
      .fetchInventory,
    ])
    #expect(model.notices.isEmpty)
  }
}
