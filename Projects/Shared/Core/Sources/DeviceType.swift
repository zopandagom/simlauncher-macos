/// 시뮬레이터 기기 종류 (simctl devicetypes 한 항목).
public struct DeviceType: Identifiable, Hashable, Sendable {
  /// simctl 기기 종류 식별자 (예: "com.apple.CoreSimulator.SimDeviceType.iPhone-17").
  public struct ID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }
  }

  public let id: ID
  /// 화면에 그대로 보이는 이름 (예: "iPhone 17"). 생성 시트의 기본 기기 이름.
  public let name: String
  public let family: VirtualDevice.Family

  public init(id: ID, name: String, family: VirtualDevice.Family) {
    self.id = id
    self.name = name
    self.family = family
  }
}
