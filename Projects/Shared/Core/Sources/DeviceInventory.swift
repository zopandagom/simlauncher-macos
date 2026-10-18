/// simctl 이 알려 준 기기·런타임 전체. 화면 표시용 필터를 거치기 전이라 모든 플랫폼이 들어 있다.
public struct DeviceInventory: Hashable, Sendable {
  public let devices: [VirtualDevice]
  public let runtimes: [DeviceRuntime]

  public init(devices: [VirtualDevice], runtimes: [DeviceRuntime]) {
    self.devices = devices
    self.runtimes = runtimes
  }
}
