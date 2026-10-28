import Foundation
import Testing
@testable import Core

struct AndroidDeviceListTests {
  @Test("표시 이름 순서(숫자 인식), 같으면 AVD 이름 순서이고 쓸 수 없는 기기도 넣는다")
  func order() {
    let list = AndroidDeviceList(devices: [
      Self.device("c", displayName: "Phone 10"),
      Self.device("b", displayName: "phone 2", availability: .unavailable(.folderMissing)),
      Self.device("z", displayName: "Alpha"),
      Self.device("a", displayName: "Alpha"),
    ])

    #expect(list.devices.map(\.id.rawValue) == ["a", "z", "b", "c"])
    #expect(list.emptyReason == nil)
    #expect(list.device(id: AndroidVirtualDevice.ID("b"))?.displayName == "phone 2")
    #expect(list.device(id: AndroidVirtualDevice.ID("missing")) == nil)
  }

  @Test("기기가 없으면 noDevices")
  func empty() {
    let list = AndroidDeviceList(devices: [])

    #expect(list.devices.isEmpty)
    #expect(list.emptyReason == .noDevices)
  }

  // MARK: - 행별 허용

  @Test("쓸 수 있고 꺼진 기기만 켤 수 있다")
  func canBoot() {
    #expect(Self.device(state: .shutdown).canBoot)
    #expect(!Self.device(state: .booting).canBoot)
    #expect(!Self.device(state: .booted).canBoot)
    #expect(!Self.device(state: .shutdown, availability: .unavailable(.unsupportedName)).canBoot)
  }

  @Test("켜는 중·켜짐이면 끌 수 있다 (쓸 수 없는 기기도)")
  func canShutdown() {
    #expect(!Self.device(state: .shutdown).canShutdown)
    #expect(Self.device(state: .booting).canShutdown)
    #expect(Self.device(state: .booted).canShutdown)
    #expect(Self.device(state: .booted, availability: .unavailable(.systemImageMissing(nil))).canShutdown)
  }

  @Test("꺼진 기기만 삭제할 수 있다 (쓸 수 없어도)")
  func delete() {
    #expect(Self.device(state: .shutdown).deleteAvailability == .allowed)
    #expect(Self.device(state: .shutdown, availability: .unavailable(.unsupportedName)).deleteAvailability == .allowed)
    #expect(Self.device(state: .booting).deleteAvailability == .blocked(.notShutdown))
    #expect(Self.device(state: .booted).deleteAvailability == .blocked(.notShutdown))
  }

  @Test("초기화는 쓸 수 없으면 먼저 막히고, 쓸 수 있으면 꺼진 기기만")
  func erase() {
    #expect(Self.device(state: .shutdown).eraseAvailability == .allowed)
    #expect(Self.device(state: .booted).eraseAvailability == .blocked(.notShutdown))
    #expect(Self.device(state: .booting).eraseAvailability == .blocked(.notShutdown))
    #expect(
      Self.device(state: .booted, availability: .unavailable(.unsupportedABI("x86_64"))).eraseAvailability
        == .blocked(.unavailable)
    )
    #expect(
      Self.device(state: .shutdown, availability: .unavailable(.configUnreadable)).eraseAvailability
        == .blocked(.unavailable)
    )
  }

  // MARK: - 도우미

  static func device(
    _ id: String = "Pixel_9",
    displayName: String = "Pixel 9",
    state: AndroidVirtualDevice.State = .shutdown,
    availability: AndroidVirtualDevice.Availability = .available
  ) -> AndroidVirtualDevice {
    AndroidVirtualDevice(
      id: AndroidVirtualDevice.ID(id),
      displayName: displayName,
      systemImage: AndroidSystemImageRef(apiFolder: "android-37.0", tag: "google_apis", abi: "arm64-v8a"),
      formFactor: .phone,
      state: state,
      availability: availability
    )
  }
}
