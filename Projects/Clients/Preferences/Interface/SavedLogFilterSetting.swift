import Core

/// 저장된 로그 필터 목록과 잠금 여부.
public struct SavedLogFilterSetting: Hashable, Sendable {
  /// 빈 목록, 잠기지 않음.
  public static let empty = SavedLogFilterSetting(filters: [], isLocked: false)

  /// 읽은 항목을 저장 순서대로, 같은 이름(대소문자 무시)은 앞 것만 (Core `SavedLogFilterList.visible`).
  /// 읽을 수 없는 항목은 들어 있지 않다.
  public let filters: [SavedLogFilter]
  /// 관리자가 이 키를 강제했다 (`objectIsForced`). 목록을 읽을 수는 있지만 저장·삭제할 수 없다.
  public let isLocked: Bool

  public init(filters: [SavedLogFilter], isLocked: Bool) {
    self.filters = filters
    self.isLocked = isLocked
  }
}
