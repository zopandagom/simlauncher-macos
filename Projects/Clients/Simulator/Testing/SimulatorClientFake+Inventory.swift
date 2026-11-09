import Core

// MARK: - 목록 갱신 (기기만 바꾸고 런타임·기기 종류는 그대로)

extension SimulatorClientFake {
  static func inventory(
    _ inventory: DeviceInventory,
    setting id: VirtualDevice.ID,
    to newState: VirtualDevice.State
  ) -> DeviceInventory {
    let devices = inventory.devices.map { device in
      guard device.id == id else { return device }
      return VirtualDevice(
        id: device.id,
        name: device.name,
        family: device.family,
        state: newState,
        availability: device.availability,
        runtime: device.runtime
      )
    }
    return Self.inventory(inventory, devices: devices)
  }

  /// 기기만 바꾸고 런타임·기기 종류는 그대로 둔 목록.
  static func inventory(_ inventory: DeviceInventory, devices: [VirtualDevice]) -> DeviceInventory {
    DeviceInventory(devices: devices, runtimes: inventory.runtimes, deviceTypes: inventory.deviceTypes)
  }
}
