import Core
import Foundation
import SimulatorInterface
import Testing
@testable import SimulatorImpl

struct SimctlListDecoderTests {
  private static let iOS27 = DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-27-0")

  @Test("런타임 필드를 읽는다")
  func decodesRuntimes() throws {
    let inventory = try SimctlListDecoder.inventory(from: Fixture.data("simctl-list"))

    #expect(inventory.runtimes == [
      DeviceRuntime(id: Self.iOS27, platform: .iOS, version: OSVersion(major: 27), name: "iOS 27.0", isAvailable: true),
      DeviceRuntime(
        id: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.watchOS-27-0"),
        platform: .watchOS,
        version: OSVersion(major: 27),
        name: "watchOS 27.0",
        isAvailable: true
      ),
      DeviceRuntime(
        id: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-25-0"),
        platform: .iOS,
        version: OSVersion(major: 25),
        name: "iOS 25.0",
        isAvailable: false
      ),
    ])
  }

  @Test("기기 필드를 읽고 런타임·기기 종류와 결합한다. watch 기기도 담는다")
  func decodesDevices() throws {
    let inventory = try SimctlListDecoder.inventory(from: Fixture.data("simctl-list"))
    let devices = Dictionary(uniqueKeysWithValues: inventory.devices.map { ($0.id.rawValue, $0) })

    #expect(inventory.devices.count == 9)
    let iPhone = try #require(devices["00000000-0000-0000-0000-000000000001"])
    #expect(iPhone.name == "iPhone 17")
    #expect(iPhone.family == .phone)
    #expect(iPhone.state == .booted)
    #expect(iPhone.availability == .available)
    #expect(iPhone.runtime.id == Self.iOS27)
    #expect(iPhone.runtime.isAvailable)

    let iPad = try #require(devices["00000000-0000-0000-0000-000000000002"])
    #expect(iPad.family == .tablet)
    #expect(iPad.state == .shutdown)

    let watch = try #require(devices["00000000-0000-0000-0000-000000000006"])
    #expect(watch.family == .watch)
    #expect(watch.runtime.platform == .watchOS)

    #expect(devices["00000000-0000-0000-0000-000000000003"]?.state == .shuttingDown)
    #expect(devices["00000000-0000-0000-0000-000000000004"]?.state == .unknown)
  }

  @Test(
    "쓸 수 없는 기기의 이유를 런타임·기기 종류 목록과 대조해 정한다",
    arguments: [
      ("00000000-0000-0000-0000-000000000007", VirtualDevice.UnavailableReason.runtimeNotInstalled),
      ("00000000-0000-0000-0000-000000000008", .runtimeUnavailable),
      ("00000000-0000-0000-0000-000000000005", .deviceTypeNotSupported),
      ("00000000-0000-0000-0000-000000000009", .unknown),
    ]
  )
  func unavailableReasons(udid: String, expected: VirtualDevice.UnavailableReason) throws {
    let inventory = try SimctlListDecoder.inventory(from: Fixture.data("simctl-list"))
    let device = try #require(inventory.devices.first { $0.id.rawValue == udid })
    #expect(device.availability == .unavailable(expected))
  }

  @Test("runtimes 에 없는 런타임은 식별자에서 만들고 쓸 수 없다")
  func runtimeMissingFromRuntimes() throws {
    let inventory = try SimctlListDecoder.inventory(from: Fixture.data("simctl-list"))
    let device = try #require(inventory.devices.first { $0.id.rawValue == "00000000-0000-0000-0000-000000000007" })
    #expect(device.runtime == DeviceRuntime(
      id: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-26-0"),
      platform: .iOS,
      version: OSVersion(major: 26),
      name: "iOS 26.0",
      isAvailable: false
    ))
    #expect(device.family == .phone)
  }

  @Test("런타임 식별자에서 플랫폼·버전·이름을 만든다")
  func runtimeFromIdentifier() {
    let runtime = SimctlListDecoder.runtime(fromIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-1")
    #expect(runtime.platform == .iOS)
    #expect(runtime.version == OSVersion(major: 27, minor: 1))
    #expect(runtime.name == "iOS 27.1")
    #expect(!runtime.isAvailable)

    let odd = SimctlListDecoder.runtime(fromIdentifier: "something")
    #expect(odd.platform == .other)
    #expect(odd.name == "something")
  }

  @Test(
    "기기 상태 문자열을 바꾸고, 모르는 값은 unknown",
    arguments: [
      ("Shutdown", VirtualDevice.State.shutdown),
      ("Booted", .booted),
      ("Booting", .booting),
      ("Shutting Down", .shuttingDown),
      ("Creating", .unknown),
      ("", .unknown),
    ]
  )
  func states(raw: String, expected: VirtualDevice.State) {
    #expect(SimctlListDecoder.state(raw) == expected)
  }

  @Test(
    "기기 종류의 productFamily 를 바꾼다",
    arguments: [
      ("iPhone", VirtualDevice.Family.phone),
      ("iPad", .tablet),
      ("Apple Watch", .watch),
      ("Apple TV", .tv),
      ("Apple Vision", .vision),
      ("Mac", .other),
    ]
  )
  func families(raw: String, expected: VirtualDevice.Family) {
    #expect(SimctlListDecoder.family(raw) == expected)
  }

  @Test("빈 목록 픽스처는 기기·런타임이 없다")
  func emptyFixture() throws {
    let inventory = try SimctlListDecoder.inventory(from: Fixture.data("simctl-list-empty"))
    #expect(inventory == DeviceInventory(devices: [], runtimes: []))
  }

  @Test("JSON 이 아니거나 필요한 키가 없으면 unexpectedOutput", arguments: ["", "not json", "{}", "{\"devices\":[]}"])
  func brokenJSON(text: String) {
    #expect(throws: SimulatorError.unexpectedOutput) {
      try SimctlListDecoder.inventory(from: Data(text.utf8))
    }
  }
}
