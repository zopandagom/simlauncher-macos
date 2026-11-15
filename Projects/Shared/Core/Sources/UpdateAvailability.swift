/// 지금 버전·최신 버전·건너뛴 버전으로 정한 결과 (여러 Client 결과를 받아 판단하는 규칙, CONVENTIONS §3).
public enum UpdateAvailability: Hashable, Sendable {
  case newer(AppVersion, skipped: Bool)
  case upToDate
  /// 이 앱의 버전을 읽지 못했다 (Info.plist).
  case currentUnknown
  /// 최신 릴리스의 버전 값이 숫자 버전이 아니다.
  case latestUnrecognized

  /// current nil → .currentUnknown (latest 와 관계없이), latest nil → .latestUnrecognized,
  /// latest > current → .newer(latest, skipped: skipped.contains(latest)), 아니면 .upToDate (지금이 더 높아도).
  public static func judge(current: AppVersion?, latest: AppVersion?, skipped: Set<AppVersion>) -> UpdateAvailability {
    guard let current else {
      return .currentUnknown
    }
    guard let latest else {
      return .latestUnrecognized
    }
    guard latest > current else {
      return .upToDate
    }
    return .newer(latest, skipped: skipped.contains(latest))
  }
}
