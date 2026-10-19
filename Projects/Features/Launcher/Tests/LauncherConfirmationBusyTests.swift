import Core
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

@MainActor
struct LauncherConfirmationBusyTests: LauncherModelTesting {
  @Test(
    "확인한 기기가 켜는 중이고 꺼짐이 아니면, 꺼짐 알림보다 진행 중 확인이 먼저라 조용히 끝난다",
    arguments: [DeviceConfirmation.Action.delete, .erase]
  )
  func busyCheckComesBeforeNotShutdownNotice(action: DeviceConfirmation.Action) async {
    let (model, fake) = await Self.loadedModel()
    let confirmation = DeviceConfirmation(
      action: action,
      deviceID: SampleID.iPhoneOff,
      device: Self.label(SampleID.iPhoneOff)
    )
    fake.suspendBoots()
    let boot = Task { await model.bootButtonTapped(SampleID.iPhoneOff) }
    await Self.waitUntil { fake.calls.contains(.boot(SampleID.iPhoneOff)) }
    // 켜는 동안 다시 읽은 목록에서 그 기기가 켜는 중으로 보인다.
    fake.setInventory(Self.inventory(SampleID.iPhoneOff, state: .booting))
    await model.refreshButtonTapped()
    #expect(Self.device(SampleID.iPhoneOff, in: model)?.state == .booting)
    #expect(model.busyDeviceIDs == [SampleID.iPhoneOff])

    await model.confirmationConfirmed(confirmation)

    #expect(model.notices.isEmpty)
    #expect(!fake.calls.contains(.delete(SampleID.iPhoneOff)))
    #expect(!fake.calls.contains(.erase(SampleID.iPhoneOff)))

    fake.resumeBoots()
    await boot.value
  }

  /// 샘플 목록에서 기기 하나의 상태만 바꾼 목록.
  private static func inventory(_ id: VirtualDevice.ID, state: VirtualDevice.State) -> DeviceInventory {
    let sample = DeviceInventory.sample
    return DeviceInventory(
      devices: sample.devices.map { device in
        guard device.id == id else { return device }
        return VirtualDevice(
          id: device.id,
          name: device.name,
          family: device.family,
          state: state,
          availability: device.availability,
          runtime: device.runtime
        )
      },
      runtimes: sample.runtimes,
      deviceTypes: sample.deviceTypes
    )
  }
}
