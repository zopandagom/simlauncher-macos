import Foundation

/// 배너 닫기(×): 그 버전을 24시간 숨긴다. 저장 키 `DismissedUpdateBanner`.
/// 숨김은 그 버전에만 걸려, 더 새 버전은 바로 보인다.
public struct UpdateBannerDismissal: Hashable, Sendable {
  /// 숨김 길이: 24시간.
  public static let duration: TimeInterval = 86400

  public let version: AppVersion
  public let dismissedAt: Date

  public init(version: AppVersion, dismissedAt: Date) {
    self.version = version
    self.dismissedAt = dismissedAt
  }

  /// 이 숨김이 지금 `version` 배너를 가리는가: 같은 버전이고, dismissedAt ≤ now 이고, now - dismissedAt < duration.
  /// 다른(더 새) 버전은 가리지 않는다. dismissedAt 이 미래(시계가 뒤로 감)면 가리지 않는다.
  public func hides(_ version: AppVersion, now: Date) -> Bool {
    guard version == self.version, self.dismissedAt <= now else {
      return false
    }
    return now.timeIntervalSince(self.dismissedAt) < Self.duration
  }
}
