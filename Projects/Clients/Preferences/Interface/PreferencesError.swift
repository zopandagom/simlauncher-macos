/// 설정을 쓰지 않은 이유. 화면 문구는 Feature 가 정한다.
public enum PreferencesError: Error, Hashable, Sendable {
  /// 관리자가 강제한 키라 쓰지 않았다.
  case locked
  /// 같은 카탈로그가 이미 있다 (화면이 읽은 뒤 바깥에서 들어온 경우).
  case duplicate
}
