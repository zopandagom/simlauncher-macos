import AppBundleTesting
import Core
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

@MainActor
struct LauncherDeleteEraseTests: LauncherModelTesting {
  // MARK: - 확인 띄우기

  @Test("꺼진 기기의 삭제·초기화를 누르면 확인을 기다리고 아무것도 부르지 않는다", arguments: [
    DeviceConfirmation.Action.delete, .erase,
  ])
  func tappingAsksConfirmation(action: DeviceConfirmation.Action) async {
    let (model, fake) = await Self.loadedModel()

    Self.tap(action, SampleID.iPhoneOff, on: model)

    #expect(
      model.pendingConfirmation == DeviceConfirmation(
        action: action,
        deviceID: SampleID.iPhoneOff,
        device: Self.label(SampleID.iPhoneOff)
      )
    )
    #expect(fake.calls == [.fetchInventory])
  }

  @Test("켜진 기기는 삭제·초기화 확인을 띄우지 않는다", arguments: [DeviceConfirmation.Action.delete, .erase])
  func bootedDeviceIsBlocked(action: DeviceConfirmation.Action) async {
    let (model, _) = await Self.loadedModel()

    Self.tap(action, SampleID.iPhoneOn, on: model)

    #expect(model.pendingConfirmation == nil)
  }

  @Test("쓸 수 없는 기기는 삭제만 확인을 띄운다")
  func unavailableDeviceCanOnlyBeDeleted() async {
    let (model, _) = await Self.loadedModel()

    model.eraseButtonTapped(SampleID.unavailableIPhone)
    #expect(model.pendingConfirmation == nil)

    model.deleteButtonTapped(SampleID.unavailableIPhone)
    #expect(model.pendingConfirmation?.action == .delete)
    #expect(model.pendingConfirmation?.deviceID == SampleID.unavailableIPhone)
  }

  @Test("목록에 없는 기기·읽기 전에는 확인을 띄우지 않는다")
  func unknownDeviceOrBeforeLoadIsIgnored() async {
    let (model, _) = await Self.loadedModel()
    model.deleteButtonTapped(SampleID.watch)
    model.eraseButtonTapped(VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF"))
    #expect(model.pendingConfirmation == nil)

    let before = LauncherModel(simulator: SimulatorClientFake(inventory: .sample), appBundle: AppBundleClientFake())
    before.deleteButtonTapped(SampleID.iPhoneOff)
    #expect(before.pendingConfirmation == nil)
  }

  @Test("확인을 기다리는 동안 다른 기기를 눌러도 처음 확인을 유지한다")
  func secondTapWhilePendingIsIgnored() async {
    let (model, _) = await Self.loadedModel()

    model.deleteButtonTapped(SampleID.iPhoneOff)
    model.eraseButtonTapped(SampleID.iPadOff)

    #expect(model.pendingConfirmation?.deviceID == SampleID.iPhoneOff)
    #expect(model.pendingConfirmation?.action == .delete)
  }

  @Test("확인을 닫으면 대기가 사라지고 아무것도 부르지 않는다")
  func dismissClearsPending() async {
    let (model, fake) = await Self.loadedModel()
    model.deleteButtonTapped(SampleID.iPhoneOff)

    model.confirmationDismissed()

    #expect(model.pendingConfirmation == nil)
    #expect(fake.calls == [.fetchInventory])
  }

  // MARK: - 실행

  @Test("삭제를 확인하면 진행 중이 되고, 삭제 → 다시 읽기 뒤 행이 사라진다")
  func deleteSuccess() async throws {
    let (model, fake) = await Self.loadedModel()
    model.deleteButtonTapped(SampleID.iPhoneOff)
    let confirmation = try #require(model.pendingConfirmation)

    fake.suspendDeletes()
    let task = Task { await model.confirmationConfirmed(confirmation) }
    await Self.waitUntil { fake.calls.contains(.delete(SampleID.iPhoneOff)) }
    #expect(model.pendingConfirmation == nil)
    #expect(model.busyDeviceIDs == [SampleID.iPhoneOff])

    fake.resumeDeletes()
    await task.value
    #expect(fake.calls == [.fetchInventory, .delete(SampleID.iPhoneOff), .fetchInventory])
    #expect(Self.device(SampleID.iPhoneOff, in: model) == nil)
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.notices.isEmpty)
  }

  @Test("초기화를 확인하면 초기화 → 다시 읽기 뒤 행이 그대로다")
  func eraseSuccess() async throws {
    let (model, fake) = await Self.loadedModel()
    model.eraseButtonTapped(SampleID.iPadOff)
    let confirmation = try #require(model.pendingConfirmation)

    await model.confirmationConfirmed(confirmation)

    #expect(fake.calls == [.fetchInventory, .erase(SampleID.iPadOff), .fetchInventory])
    #expect(Self.device(SampleID.iPadOff, in: model) != nil)
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.notices.isEmpty)
  }

  @Test("삭제·초기화가 실패하면 누른 시점의 이름으로 알리고 다시 읽으며, 진행 중을 푼다", arguments: [
    DeviceConfirmation.Action.delete, .erase,
  ])
  func failureNotifiesAndReloads(action: DeviceConfirmation.Action) async throws {
    let (model, fake) = await Self.loadedModel {
      $0.setDeleteError(.deviceNotShutdown)
      $0.setEraseError(.deviceNotShutdown)
    }
    Self.tap(action, SampleID.iPhoneOff, on: model)
    let confirmation = try #require(model.pendingConfirmation)

    await model.confirmationConfirmed(confirmation)

    let label = Self.label(SampleID.iPhoneOff)
    let expected: LauncherNotice = action == .delete
      ? .deleteFailed(label, .deviceNotShutdown)
      : .eraseFailed(label, .deviceNotShutdown)
    #expect(model.notices.map(\.notice) == [expected])
    #expect(fake.calls.count == 3)
    #expect(fake.calls.last == .fetchInventory)
    #expect(Self.device(SampleID.iPhoneOff, in: model) != nil)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("SwiftUI 처럼 닫힘이 먼저 불린 뒤 확인이 와도 실행한다")
  func confirmAfterDismissStillRuns() async throws {
    let (model, fake) = await Self.loadedModel()
    model.deleteButtonTapped(SampleID.iPhoneOff)
    let confirmation = try #require(model.pendingConfirmation)

    model.confirmationDismissed()
    await model.confirmationConfirmed(confirmation)

    #expect(fake.calls == [.fetchInventory, .delete(SampleID.iPhoneOff), .fetchInventory])
  }

  // MARK: - 기다리는 동안 바뀐 목록

  @Test("확인을 기다리는 동안 기기가 사라지면 실행하지 않고 찾을 수 없다고 알린다", arguments: [
    DeviceConfirmation.Action.delete, .erase,
  ])
  func deviceRemovedWhilePending(action: DeviceConfirmation.Action) async throws {
    let (model, fake) = await Self.loadedModel()
    Self.tap(action, SampleID.iPhoneOff, on: model)
    let confirmation = try #require(model.pendingConfirmation)
    let sample = DeviceInventory.sample
    fake.setInventory(
      DeviceInventory(
        devices: sample.devices.filter { $0.id != SampleID.iPhoneOff },
        runtimes: sample.runtimes,
        deviceTypes: sample.deviceTypes
      )
    )
    await model.refreshButtonTapped()

    await model.confirmationConfirmed(confirmation)

    let label = Self.label(SampleID.iPhoneOff)
    let expected: LauncherNotice = action == .delete
      ? .deleteFailed(label, .deviceNotFound)
      : .eraseFailed(label, .deviceNotFound)
    #expect(model.notices.map(\.notice) == [expected])
    #expect(fake.calls == [.fetchInventory, .fetchInventory])
  }

  @Test("확인을 기다리는 동안 기기가 켜지면 실행하지 않고 끈 뒤 하라고 알린다")
  func deviceBootedWhilePending() async throws {
    let (model, fake) = await Self.loadedModel()
    model.eraseButtonTapped(SampleID.iPhoneOff)
    let confirmation = try #require(model.pendingConfirmation)
    let sample = DeviceInventory.sample
    fake.setInventory(
      DeviceInventory(
        devices: sample.devices.map { device in
          guard device.id == SampleID.iPhoneOff else { return device }
          return VirtualDevice(
            id: device.id,
            name: device.name,
            family: device.family,
            state: .booted,
            availability: device.availability,
            runtime: device.runtime
          )
        },
        runtimes: sample.runtimes,
        deviceTypes: sample.deviceTypes
      )
    )
    await model.refreshButtonTapped()

    await model.confirmationConfirmed(confirmation)

    #expect(model.notices.map(\.notice) == [.eraseFailed(Self.label(SampleID.iPhoneOff), .deviceNotShutdown)])
    #expect(fake.calls == [.fetchInventory, .fetchInventory])
  }

  // MARK: - 다른 작업과 겹침

  @Test("켜는 중인 기기는 삭제 확인을 띄우지 않고, 지우는 중인 기기는 켜지 않는다")
  func busyDeviceBlocksOtherActions() async throws {
    let (model, fake) = await Self.loadedModel()

    fake.suspendBoots()
    let boot = Task { await model.bootButtonTapped(SampleID.iPhoneOff) }
    await Self.waitUntil { fake.calls.contains(.boot(SampleID.iPhoneOff)) }
    model.deleteButtonTapped(SampleID.iPhoneOff)
    #expect(model.pendingConfirmation == nil)
    fake.resumeBoots()
    await boot.value

    model.deleteButtonTapped(SampleID.iPadOff)
    let confirmation = try #require(model.pendingConfirmation)
    fake.suspendDeletes()
    let delete = Task { await model.confirmationConfirmed(confirmation) }
    await Self.waitUntil { fake.calls.contains(.delete(SampleID.iPadOff)) }
    await model.bootButtonTapped(SampleID.iPadOff)
    #expect(!fake.calls.contains(.boot(SampleID.iPadOff)))
    fake.resumeDeletes()
    await delete.value
  }

  @Test("다른 두 기기의 켜기와 삭제가 겹쳐도 각자 끝난다")
  func bootAndDeleteOnDifferentDevices() async throws {
    let (model, fake) = await Self.loadedModel()
    model.deleteButtonTapped(SampleID.iPadOff)
    let confirmation = try #require(model.pendingConfirmation)

    fake.suspendBoots()
    fake.suspendDeletes()
    let boot = Task { await model.bootButtonTapped(SampleID.iPhoneOff) }
    let delete = Task { await model.confirmationConfirmed(confirmation) }
    await Self.waitUntil {
      fake.calls.contains(.boot(SampleID.iPhoneOff)) && fake.calls.contains(.delete(SampleID.iPadOff))
    }
    #expect(model.busyDeviceIDs == [SampleID.iPhoneOff, SampleID.iPadOff])

    fake.resumeBoots()
    fake.resumeDeletes()
    await boot.value
    await delete.value
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(Self.device(SampleID.iPhoneOff, in: model)?.state == .booted)
    #expect(Self.device(SampleID.iPadOff, in: model) == nil)
  }

  private static func tap(_ action: DeviceConfirmation.Action, _ id: VirtualDevice.ID, on model: LauncherModel) {
    switch action {
    case .delete: model.deleteButtonTapped(id)
    case .erase: model.eraseButtonTapped(id)
    }
  }
}
