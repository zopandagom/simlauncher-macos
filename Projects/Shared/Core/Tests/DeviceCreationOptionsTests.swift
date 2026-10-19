import Testing
@testable import Core

struct DeviceCreationOptionsTests {
  private static let iPhone17 = Self.type("iPhone-17", "iPhone 17", .phone)
  private static let iPhone17Pro = Self.type("iPhone-17-Pro", "iPhone 17 Pro", .phone)
  private static let iPadA16 = Self.type("iPad-A16", "iPad (A16)", .tablet)
  private static let watch = Self.type("Apple-Watch", "Apple Watch", .watch)
  private static let allTypes = [Self.iPhone17, Self.iPhone17Pro, Self.iPadA16, Self.watch]

  private static let iOS27 = Self.runtime("iOS-27-0", .iOS, OSVersion(major: 27), "iOS 27.0", [
    Self.iPadA16.id, Self.iPhone17Pro.id, Self.watch.id, Self.iPhone17.id,
  ])
  private static let iOS26 = Self.runtime("iOS-26-0", .iOS, OSVersion(major: 26), "iOS 26.0", [Self.iPhone17.id])

  @Test("쓸 수 있는 iOS 런타임 중 iPhone·iPad 종류가 있는 것만 담는다")
  func filtersRuntimes() {
    let watchOS = Self.runtime("watchOS-27-0", .watchOS, OSVersion(major: 27), "watchOS 27.0", [Self.watch.id])
    let unavailable = Self.runtime("iOS-25-0", .iOS, OSVersion(major: 25), "iOS 25.0", [Self.iPhone17.id], false)
    let watchOnly = Self.runtime("iOS-24-0", .iOS, OSVersion(major: 24), "iOS 24.0", [Self.watch.id])
    let unknownOnly = Self.runtime("iOS-23-0", .iOS, OSVersion(major: 23), "iOS 23.0", [DeviceType.ID("nope")])

    let options = Self.options(runtimes: [watchOS, Self.iOS26, unavailable, watchOnly, unknownOnly, Self.iOS27])

    #expect(options.runtimes == [Self.iOS27, Self.iOS26])
    #expect(!options.isEmpty)
  }

  @Test("런타임은 버전 내림차순, 같은 버전은 숫자를 인식한 이름 순서다")
  func ordersRuntimes() {
    let build10 = Self.runtime("iOS-27-0-b", .iOS, OSVersion(major: 27), "iOS 27.0 (10)", [Self.iPhone17.id])
    let build9 = Self.runtime("iOS-27-0-a", .iOS, OSVersion(major: 27), "iOS 27.0 (9)", [Self.iPhone17.id])
    let newer = Self.runtime("iOS-27-1", .iOS, OSVersion(major: 27, minor: 1), "iOS 27.1", [Self.iPhone17.id])

    let options = Self.options(runtimes: [Self.iOS26, build10, build9, newer])

    #expect(options.runtimes.map(\.name) == ["iOS 27.1", "iOS 27.0 (9)", "iOS 27.0 (10)", "iOS 26.0"])
  }

  @Test("기기 종류는 phone → tablet, 같은 종류 안은 supportedDeviceTypeIDs 순서이고 watch·모르는 ID 는 뺀다")
  func ordersDeviceTypes() {
    let runtime = Self.runtime("iOS-27-0", .iOS, OSVersion(major: 27), "iOS 27.0", [
      Self.iPadA16.id, Self.iPhone17Pro.id, DeviceType.ID("unknown"), Self.watch.id, Self.iPhone17.id,
    ])

    let options = Self.options(runtimes: [runtime])

    #expect(options.deviceTypes(for: runtime.id) == [Self.iPhone17Pro, Self.iPhone17, Self.iPadA16])
    #expect(options.deviceTypes(for: DeviceRuntime.ID("unknown")).isEmpty)
  }

  @Test("기본 런타임은 최신, 기본 기기 종류는 그 첫 종류다")
  func defaults() {
    let options = Self.options(runtimes: [Self.iOS26, Self.iOS27])

    #expect(options.defaultRuntime == Self.iOS27)
    #expect(options.defaultDeviceType(for: Self.iOS27.id) == Self.iPhone17Pro)
    #expect(options.defaultDeviceType(for: Self.iOS26.id) == Self.iPhone17)
    #expect(options.defaultDeviceType(for: DeviceRuntime.ID("unknown")) == nil)
  }

  @Test("지원하는 조합만 만들 수 있다")
  func containsOnlySupportedCombinations() {
    let unavailable = Self.runtime("iOS-25-0", .iOS, OSVersion(major: 25), "iOS 25.0", [Self.iPhone17.id], false)
    let options = Self.options(runtimes: [Self.iOS27, Self.iOS26, unavailable])

    #expect(options.contains(runtime: Self.iOS27.id, deviceType: Self.iPadA16.id))
    #expect(options.contains(runtime: Self.iOS26.id, deviceType: Self.iPhone17.id))
    #expect(!options.contains(runtime: Self.iOS26.id, deviceType: Self.iPadA16.id))
    #expect(!options.contains(runtime: Self.iOS27.id, deviceType: Self.watch.id))
    #expect(!options.contains(runtime: Self.iOS27.id, deviceType: DeviceType.ID("unknown")))
    #expect(!options.contains(runtime: DeviceRuntime.ID("unknown"), deviceType: Self.iPhone17.id))
    #expect(!options.contains(runtime: unavailable.id, deviceType: Self.iPhone17.id))
  }

  @Test("빈 목록이면 선택지가 없다")
  func emptyInventory() {
    let options = DeviceCreationOptions(inventory: DeviceInventory(devices: [], runtimes: [], deviceTypes: []))
    #expect(options.isEmpty)
    #expect(options.runtimes.isEmpty)
    #expect(options.defaultRuntime == nil)
  }

  @Test("기기 종류 목록이 비면 런타임이 지원한다고 해도 선택지가 없다")
  func noDeviceTypes() {
    let options = DeviceCreationOptions(inventory: DeviceInventory(
      devices: [],
      runtimes: [Self.iOS27],
      deviceTypes: []
    ))
    #expect(options.isEmpty)
  }

  private static func options(runtimes: [DeviceRuntime]) -> DeviceCreationOptions {
    DeviceCreationOptions(inventory: DeviceInventory(devices: [], runtimes: runtimes, deviceTypes: self.allTypes))
  }

  private static func type(_ suffix: String, _ name: String, _ family: VirtualDevice.Family) -> DeviceType {
    DeviceType(id: DeviceType.ID("com.apple.CoreSimulator.SimDeviceType.\(suffix)"), name: name, family: family)
  }

  private static func runtime(
    _ suffix: String,
    _ platform: DevicePlatform,
    _ version: OSVersion,
    _ name: String,
    _ supported: [DeviceType.ID],
    _ isAvailable: Bool = true
  ) -> DeviceRuntime {
    DeviceRuntime(
      id: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.\(suffix)"),
      platform: platform,
      version: version,
      name: name,
      isAvailable: isAvailable,
      supportedDeviceTypeIDs: supported
    )
  }
}
