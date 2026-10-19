import Testing
@testable import Core

struct AppInstallAvailabilityTests {
  @Test("쓸 수 있고 꺼졌거나 켜진 기기에는 앱을 설치할 수 있다", arguments: [VirtualDevice.State.shutdown, .booted])
  func allowed(state: VirtualDevice.State) {
    #expect(Self.device(state: state, availability: .available).appInstallAvailability == .allowed)
  }

  @Test("켜는 중·끄는 중·상태를 모르는 기기는 막힌다", arguments: [VirtualDevice.State.booting, .shuttingDown, .unknown])
  func stateChanging(state: VirtualDevice.State) {
    #expect(Self.device(state: state, availability: .available).appInstallAvailability == .blocked(.stateChanging))
  }

  @Test(
    "쓸 수 없는 기기는 상태보다 먼저 쓸 수 없어서 막힌다",
    arguments: [VirtualDevice.State.shutdown, .booted, .booting]
  )
  func unavailable(state: VirtualDevice.State) {
    let device = Self.device(state: state, availability: .unavailable(.runtimeNotInstalled))
    #expect(device.appInstallAvailability == .blocked(.unavailable))
  }

  private static func device(state: VirtualDevice.State, availability: VirtualDevice.Availability) -> VirtualDevice {
    VirtualDevice(
      id: VirtualDevice.ID("00000000-0000-0000-0000-000000000001"),
      name: "iPhone 17",
      family: .phone,
      state: state,
      availability: availability,
      runtime: DeviceRuntime(
        id: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-27-0"),
        platform: .iOS,
        version: OSVersion(major: 27),
        name: "iOS 27.0",
        isAvailable: true,
        supportedDeviceTypeIDs: []
      )
    )
  }
}
