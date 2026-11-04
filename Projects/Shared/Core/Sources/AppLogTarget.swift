/// 로그 창 하나의 대상: 플랫폼 + 기기 ID. 기기당 창 하나라 앱·세션은 담지 않는다.
/// `WindowGroup(id: AppLogTarget.windowID, for: AppLogTarget.self)` 의 값이라 Codable·Hashable 이다
/// (같은 값으로 창을 다시 열면 새 창이 아니라 그 창이 앞으로 온다, 측정).
public struct AppLogTarget: Hashable, Codable, Sendable {
  public enum Platform: String, Hashable, Codable, Sendable {
    case iOS = "ios"
    case android
  }

  /// 로그 창 `WindowGroup` 의 id.
  public static let windowID = "device-log"

  public let platform: Platform
  /// iOS 는 `VirtualDevice.ID.rawValue`(UDID), Android 는 AVD 이름.
  public let deviceID: String

  public init(platform: Platform, deviceID: String) {
    self.platform = platform
    self.deviceID = deviceID
  }

  /// iOS 시뮬레이터 기기의 로그 창 대상.
  public static func iOS(_ id: VirtualDevice.ID) -> AppLogTarget {
    AppLogTarget(platform: .iOS, deviceID: id.rawValue)
  }
}
