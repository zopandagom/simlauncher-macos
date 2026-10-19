/// simctl 이 알려 준 기기·런타임·기기 종류 전체. 화면 표시용 필터를 거치기 전이라 모든 플랫폼이 들어 있다.
public struct DeviceInventory: Hashable, Sendable {
  public let devices: [VirtualDevice]
  public let runtimes: [DeviceRuntime]
  /// 모든 플랫폼의 기기 종류 (simctl devicetypes).
  public let deviceTypes: [DeviceType]

  /// 기본값을 두지 않는다: 목록을 다시 만드는 경로가 기기 종류를 조용히 잃지 않게 컴파일러가 잡는다.
  public init(devices: [VirtualDevice], runtimes: [DeviceRuntime], deviceTypes: [DeviceType]) {
    self.devices = devices
    self.runtimes = runtimes
    self.deviceTypes = deviceTypes
  }
}
