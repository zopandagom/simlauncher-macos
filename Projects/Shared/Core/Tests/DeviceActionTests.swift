import Testing
@testable import Core

struct DeviceActionTests {
  @Test("꺼진·쓸 수 있는 기기는 삭제·초기화할 수 있다")
  func shutdownAvailable() {
    let device = Self.device(state: .shutdown, availability: .available)
    #expect(device.deleteAvailability == .allowed)
    #expect(device.eraseAvailability == .allowed)
  }

  @Test(
    "꺼지지 않은 기기는 삭제·초기화가 막힌다",
    arguments: [VirtualDevice.State.booted, .booting, .shuttingDown, .unknown]
  )
  func notShutdown(state: VirtualDevice.State) {
    let device = Self.device(state: state, availability: .available)
    #expect(device.deleteAvailability == .blocked(.notShutdown))
    #expect(device.eraseAvailability == .blocked(.notShutdown))
  }

  @Test("쓸 수 없는 꺼진 기기는 삭제만 할 수 있다")
  func unavailableShutdown() {
    let device = Self.device(state: .shutdown, availability: .unavailable(.runtimeNotInstalled))
    #expect(device.deleteAvailability == .allowed)
    #expect(device.eraseAvailability == .blocked(.unavailable))
  }

  @Test("쓸 수 없는 켜진 기기는 삭제는 꺼짐 때문에, 초기화는 쓸 수 없어서 막힌다")
  func unavailableBooted() {
    let device = Self.device(state: .booted, availability: .unavailable(.unknown))
    #expect(device.deleteAvailability == .blocked(.notShutdown))
    #expect(device.eraseAvailability == .blocked(.unavailable))
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
