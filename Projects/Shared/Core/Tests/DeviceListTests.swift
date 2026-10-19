import Foundation
import Testing
@testable import Core

struct DeviceListTests {
  private static let iOS27 = Self.runtime("iOS-27-0", .iOS, OSVersion(major: 27), "iOS 27.0")
  private static let iOS26 = Self.runtime("iOS-26-0", .iOS, OSVersion(major: 26), "iOS 26.0")
  private static let iOS26Point1 = Self.runtime("iOS-26-1", .iOS, OSVersion(major: 26, minor: 1), "iOS 26.1")
  private static let iOS25Unavailable = Self.runtime("iOS-25-0", .iOS, OSVersion(major: 25), "iOS 25.0", false)
  private static let watchOS27 = Self.runtime("watchOS-27-0", .watchOS, OSVersion(major: 27), "watchOS 27.0")
  private static let tvOS27 = Self.runtime("tvOS-27-0", .tvOS, OSVersion(major: 27), "tvOS 27.0")

  @Test("iOS 런타임 기기는 쓸 수 없어도 보이고, 다른 플랫폼 기기는 숨긴다")
  func isListed() {
    #expect(DeviceList.isListed(Self.device(1, runtime: Self.iOS27)))
    #expect(DeviceList.isListed(Self.device(2, availability: .unavailable(.unknown), runtime: Self.iOS25Unavailable)))
    #expect(!DeviceList.isListed(Self.device(3, family: .watch, runtime: Self.watchOS27)))
    #expect(!DeviceList.isListed(Self.device(4, family: .tv, runtime: Self.tvOS27)))
    let other = Self.runtime("other", .other, OSVersion(major: 1), "Other")
    #expect(!DeviceList.isListed(Self.device(5, runtime: other)))
  }

  @Test("런타임별로 묶고 섹션은 버전 내림차순, 같은 버전은 이름 순서다")
  func groupsAndOrdersSections() {
    let sameVersionB = Self.runtime("iOS-26-0-b", .iOS, OSVersion(major: 26), "iOS 26.0 (B)")
    let inventory = DeviceInventory(
      devices: [
        Self.device(1, runtime: Self.iOS26),
        Self.device(2, runtime: Self.iOS27),
        Self.device(3, runtime: sameVersionB),
        Self.device(4, runtime: Self.iOS26Point1),
        Self.device(5, runtime: Self.iOS27),
        Self.device(6, family: .watch, runtime: Self.watchOS27),
      ],
      runtimes: [Self.iOS26, Self.iOS27, sameVersionB, Self.iOS26Point1, Self.watchOS27]
    )

    let list = DeviceList(inventory: inventory)

    #expect(list.sections.map(\.runtime.name) == ["iOS 27.0", "iOS 26.1", "iOS 26.0", "iOS 26.0 (B)"])
    #expect(list.sections[0].devices.map(\.id) == [Self.id(2), Self.id(5)])
    #expect(list.sections.map(\.id) == list.sections.map(\.runtime.id))
    #expect(list.emptyReason == nil)
  }

  @Test("섹션 안은 iPhone → iPad → 그 밖, 다음 숫자를 인식한 이름 순서다")
  func ordersDevicesInSection() {
    let inventory = DeviceInventory(
      devices: [
        Self.device(1, name: "iPad Pro", family: .tablet, runtime: Self.iOS27),
        Self.device(2, name: "iPhone 17", runtime: Self.iOS27),
        Self.device(3, name: "Mystery", family: .other, runtime: Self.iOS27),
        Self.device(4, name: "iPhone 9", runtime: Self.iOS27),
        Self.device(5, name: "iPad Air", family: .tablet, runtime: Self.iOS27),
        Self.device(6, name: "iphone 10", runtime: Self.iOS27),
      ],
      runtimes: [Self.iOS27]
    )

    let names = DeviceList(inventory: inventory).sections.first?.devices.map(\.name)

    #expect(names == ["iPhone 9", "iphone 10", "iPhone 17", "iPad Air", "iPad Pro", "Mystery"])
  }

  @Test("이름이 같으면 식별자 순서로, 입력 순서와 무관하게 같은 결과다")
  func sameNamesAreStable() {
    let devices = [
      Self.device(2, name: "iPhone 17", runtime: Self.iOS27),
      Self.device(1, name: "iPhone 17", runtime: Self.iOS27),
    ]
    let forward = DeviceList(inventory: DeviceInventory(devices: devices, runtimes: [Self.iOS27]))
    let reversed = DeviceList(inventory: DeviceInventory(devices: devices.reversed(), runtimes: [Self.iOS27]))

    #expect(forward.sections.first?.devices.map(\.id) == [Self.id(1), Self.id(2)])
    #expect(forward == reversed)
  }

  @Test(
    "보일 기기가 없으면 쓸 수 있는 iOS 런타임 유무로 빈 이유를 정한다",
    arguments: [
      (DeviceInventory(devices: [], runtimes: []), DeviceListEmptyReason.noIOSRuntime),
      (DeviceInventory(devices: [], runtimes: [Self.iOS25Unavailable]), .noIOSRuntime),
      (
        DeviceInventory(devices: [Self.device(1, family: .watch, runtime: Self.watchOS27)], runtimes: [Self.watchOS27]),
        .noIOSRuntime
      ),
      (DeviceInventory(devices: [], runtimes: [Self.iOS27]), .noDevices),
      (
        DeviceInventory(
          devices: [Self.device(1, family: .watch, runtime: Self.watchOS27)],
          runtimes: [Self.iOS27, Self.watchOS27]
        ),
        .noDevices
      ),
    ]
  )
  func emptyReason(inventory: DeviceInventory, expected: DeviceListEmptyReason) {
    let list = DeviceList(inventory: inventory)
    #expect(list.sections.isEmpty)
    #expect(list.emptyReason == expected)
  }

  @Test("보일 기기가 있으면 빈 이유가 없다. 쓸 수 없는 iOS 기기만 있어도 보인다")
  func noEmptyReasonWhenListed() {
    let unavailable = Self.device(1, availability: .unavailable(.runtimeNotInstalled), runtime: Self.iOS25Unavailable)
    let list = DeviceList(inventory: DeviceInventory(devices: [unavailable], runtimes: []))
    #expect(list.sections.count == 1)
    #expect(list.emptyReason == nil)
  }

  @Test("식별자로 보이는 기기를 찾고, 숨긴 기기나 없는 기기는 nil")
  func findsDeviceByID() {
    let inventory = DeviceInventory(
      devices: [
        Self.device(1, runtime: Self.iOS27),
        Self.device(2, runtime: Self.iOS26),
        Self.device(3, family: .watch, runtime: Self.watchOS27),
      ],
      runtimes: [Self.iOS27, Self.iOS26, Self.watchOS27]
    )
    let list = DeviceList(inventory: inventory)

    #expect(list.device(id: Self.id(2))?.runtime == Self.iOS26)
    #expect(list.device(id: Self.id(3)) == nil)
    #expect(list.device(id: Self.id(9)) == nil)
  }

  @Test("sections·emptyReason 을 그대로 받는 생성자는 값을 바꾸지 않는다")
  func memberwiseInit() {
    let section = DeviceSection(runtime: Self.iOS26, devices: [Self.device(1, runtime: Self.iOS26)])
    let list = DeviceList(sections: [section], emptyReason: nil)
    #expect(list.sections == [section])
    #expect(DeviceList(sections: [], emptyReason: .noDevices).emptyReason == .noDevices)
  }

  private static func id(_ number: Int) -> VirtualDevice.ID {
    VirtualDevice.ID("00000000-0000-0000-0000-\(String(format: "%012d", number))")
  }

  private static func runtime(
    _ suffix: String,
    _ platform: DevicePlatform,
    _ version: OSVersion,
    _ name: String,
    _ isAvailable: Bool = true
  ) -> DeviceRuntime {
    DeviceRuntime(
      id: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.\(suffix)"),
      platform: platform,
      version: version,
      name: name,
      isAvailable: isAvailable
    )
  }

  private static func device(
    _ number: Int,
    name: String? = nil,
    family: VirtualDevice.Family = .phone,
    availability: VirtualDevice.Availability = .available,
    runtime: DeviceRuntime
  ) -> VirtualDevice {
    VirtualDevice(
      id: self.id(number),
      name: name ?? "Device \(number)",
      family: family,
      state: .shutdown,
      availability: availability,
      runtime: runtime
    )
  }
}
