/// 레이아웃 창 하나의 대상: 플랫폼 + 기기 ID. 기기당 창 하나다.
/// `WindowGroup(id: LayoutTarget.windowID, for: LayoutTarget.self)` 의 값이라 Codable·Hashable 이다.
/// 로그 창(`AppLogTarget`)과 다른 타입이라 두 창 그룹에 잘못 넘기면 컴파일러가 잡는다. 플랫폼 값은 로그 창과 같은 enum 이다.
public struct LayoutTarget: Hashable, Codable, Sendable {
  public typealias Platform = AppLogTarget.Platform

  /// 레이아웃 창 `WindowGroup` 의 id.
  public static let windowID = "device-layout"

  public let platform: Platform
  /// iOS 는 `VirtualDevice.ID.rawValue`(UDID), Android 는 AVD 이름.
  public let deviceID: String

  public init(platform: Platform, deviceID: String) {
    self.platform = platform
    self.deviceID = deviceID
  }

  /// iOS 시뮬레이터 기기의 레이아웃 창 대상.
  public static func iOS(_ id: VirtualDevice.ID) -> LayoutTarget {
    LayoutTarget(platform: .iOS, deviceID: id.rawValue)
  }

  /// Android 기기(AVD)의 레이아웃 창 대상.
  public static func android(_ id: AndroidVirtualDevice.ID) -> LayoutTarget {
    LayoutTarget(platform: .android, deviceID: id.rawValue)
  }
}
