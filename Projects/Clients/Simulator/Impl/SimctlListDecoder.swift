import Core
import Foundation
import SimulatorInterface

/// `xcrun simctl list -j` 출력을 `DeviceInventory` 로 바꾼다 (순수).
enum SimctlListDecoder {
  static func inventory(from data: Data) throws(SimulatorError) -> DeviceInventory {
    let list: ListDTO
    do {
      list = try JSONDecoder().decode(ListDTO.self, from: data)
    } catch {
      throw .unexpectedOutput
    }

    let runtimes = list.runtimes.map(Self.runtime(from:))
    let runtimesByID = Dictionary(runtimes.map { ($0.id, $0) }) { first, _ in first }
    let familiesByType = Dictionary(
      list.devicetypes.map { ($0.identifier, Self.family($0.productFamily)) }
    ) { first, _ in first }

    // 런타임 식별자 순서로 펼쳐 결과를 늘 같게 한다. 화면 순서는 DeviceList 가 정한다.
    let devices = list.devices.keys.sorted().flatMap { runtimeIdentifier in
      let runtimeID = DeviceRuntime.ID(runtimeIdentifier)
      let installed = runtimesByID[runtimeID]
      let runtime = installed ?? Self.runtime(fromIdentifier: runtimeIdentifier)
      return (list.devices[runtimeIdentifier] ?? []).map { device in
        let family = device.deviceTypeIdentifier.flatMap { familiesByType[$0] }
        return VirtualDevice(
          id: VirtualDevice.ID(device.udid),
          name: device.name,
          family: family ?? .other,
          state: Self.state(device.state),
          availability: Self.availability(
            isAvailable: device.isAvailable ?? false,
            runtime: installed,
            isKnownDeviceType: family != nil
          ),
          runtime: runtime
        )
      }
    }
    return DeviceInventory(devices: devices, runtimes: runtimes)
  }

  static func state(_ raw: String) -> VirtualDevice.State {
    switch raw {
    case "Shutdown": .shutdown
    case "Booted": .booted
    case "Booting": .booting
    case "Shutting Down": .shuttingDown
    default: .unknown
    }
  }

  /// devicetypes 의 `productFamily` 값. 'Apple TV'·'Apple Vision' 은 목록에서 확인한 값이다.
  static func family(_ productFamily: String?) -> VirtualDevice.Family {
    switch productFamily {
    case "iPhone": .phone
    case "iPad": .tablet
    case "Apple Watch": .watch
    case "Apple TV": .tv
    case "Apple Vision": .vision
    default: .other
    }
  }

  /// runtimes 에 없는(설치되지 않은) 런타임을 식별자에서 만든다. 항상 쓸 수 없는 런타임이다.
  /// 예: "com.apple.CoreSimulator.SimRuntime.iOS-27-1" → iOS, 27.1, "iOS 27.1".
  static func runtime(fromIdentifier identifier: String) -> DeviceRuntime {
    let id = DeviceRuntime.ID(identifier)
    let suffix = identifier.split(separator: ".").last.map(String.init) ?? identifier
    let parts = suffix.split(separator: "-").map(String.init)
    guard parts.count >= 2, let version = OSVersion(parts.dropFirst().joined(separator: ".")) else {
      return DeviceRuntime(id: id, platform: .other, version: OSVersion(major: 0), name: identifier, isAvailable: false)
    }
    let platformName = parts[0]
    return DeviceRuntime(
      id: id,
      platform: DevicePlatform(simctlPlatform: platformName),
      version: version,
      name: "\(platformName) \(parts.dropFirst().joined(separator: "."))",
      isAvailable: false
    )
  }

  private static func runtime(from dto: RuntimeDTO) -> DeviceRuntime {
    let fromIdentifier = Self.runtime(fromIdentifier: dto.identifier)
    return DeviceRuntime(
      id: DeviceRuntime.ID(dto.identifier),
      platform: dto.platform.map(DevicePlatform.init(simctlPlatform:)) ?? fromIdentifier.platform,
      version: dto.version.flatMap(OSVersion.init) ?? fromIdentifier.version,
      name: dto.name,
      isAvailable: dto.isAvailable ?? false
    )
  }

  /// simctl 의 `availabilityError` 문구는 해석하지 않고, 런타임·기기 종류 목록과 대조해 이유를 정한다.
  private static func availability(
    isAvailable: Bool,
    runtime: DeviceRuntime?,
    isKnownDeviceType: Bool
  ) -> VirtualDevice.Availability {
    if isAvailable {
      return .available
    }
    guard let runtime else { return .unavailable(.runtimeNotInstalled) }
    if !runtime.isAvailable {
      return .unavailable(.runtimeUnavailable)
    }
    if !isKnownDeviceType {
      return .unavailable(.deviceTypeNotSupported)
    }
    return .unavailable(.unknown)
  }
}

private struct ListDTO: Decodable {
  let devicetypes: [DeviceTypeDTO]
  let runtimes: [RuntimeDTO]
  let devices: [String: [DeviceDTO]]
}

private struct DeviceTypeDTO: Decodable {
  let identifier: String
  let productFamily: String?
}

private struct RuntimeDTO: Decodable {
  let identifier: String
  let platform: String?
  let version: String?
  let name: String
  let isAvailable: Bool?
}

private struct DeviceDTO: Decodable {
  let udid: String
  let name: String
  let state: String
  let isAvailable: Bool?
  let deviceTypeIdentifier: String?
}
