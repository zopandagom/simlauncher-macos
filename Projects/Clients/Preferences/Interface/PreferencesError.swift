/// 설정을 쓰지 않은 이유. 화면 문구는 Feature 가 정한다.
public enum PreferencesError: Error, Hashable, Sendable {
  /// 관리자가 강제한 키라 쓰지 않았다.
  case locked
  /// 같은 항목이 이미 있다 (카탈로그: 같은 카탈로그, 로그 필터: 같은 이름). 화면이 읽은 뒤 바깥에서 들어온 경우 포함.
  case duplicate
  /// 목록 상한(로그 필터 `SavedLogFilter.maxCount` 개)이라 더하지 않았다.
  case limitReached
}
