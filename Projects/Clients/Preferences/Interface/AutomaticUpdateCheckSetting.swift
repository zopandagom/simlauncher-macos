/// 새 버전 자동 확인 설정(키 `AutomaticUpdateCheck`)과 잠금 여부.
public struct AutomaticUpdateCheckSetting: Hashable, Sendable {
  /// 키가 없을 때: 켬, 잠기지 않음.
  public static let enabledDefault = AutomaticUpdateCheckSetting(isEnabled: true, isLocked: false)

  /// 자동 확인이 켜져 있다. 키 없음 → 켬, 읽을 수 없는 값 → 끔 (강제 값도 같다).
  public let isEnabled: Bool
  /// 관리자가 이 키를 강제했다 (`objectIsForced`). 설정 창 토글이 잠긴다.
  public let isLocked: Bool

  public init(isEnabled: Bool, isLocked: Bool) {
    self.isEnabled = isEnabled
    self.isLocked = isLocked
  }
}
