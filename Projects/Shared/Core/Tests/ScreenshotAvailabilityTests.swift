import Testing
@testable import Core

struct ScreenshotAvailabilityTests {
  @Test("쓸 수 있고 켜진 기기만 찍을 수 있다")
  func allowed() {
    #expect(Self.device(state: .booted, availability: .available).screenshotAvailability == .allowed)
  }

  @Test(
    "꺼짐·켜는 중·끄는 중·상태를 모르는 기기는 켜져 있지 않아서 막힌다",
    arguments: [VirtualDevice.State.shutdown, .booting, .shuttingDown, .unknown]
  )
  func notBooted(state: VirtualDevice.State) {
    #expect(Self.device(state: state, availability: .available).screenshotAvailability == .blocked(.notBooted))
  }

  @Test(
    "쓸 수 없는 기기는 켜져 있어도 상태보다 먼저 쓸 수 없어서 막힌다",
    arguments: [VirtualDevice.State.booted, .shutdown, .booting]
  )
  func unavailable(state: VirtualDevice.State) {
    let device = Self.device(state: state, availability: .unavailable(.runtimeUnavailable))
    #expect(device.screenshotAvailability == .blocked(.unavailable))
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
