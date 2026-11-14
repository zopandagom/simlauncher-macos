/// 기기 외관 (테스트 조건). iOS `simctl ui appearance`·Android `cmd uimode night` 가 함께 쓴다.
/// rawValue 는 명령 토큰이 아니다: 명령 인자는 각 Client Impl 이 switch 로 정한다 (simctl 은 `light`/`dark`, uimode 는 `no`/`yes`).
public enum DeviceAppearance: String, CaseIterable, Hashable, Sendable {
  case light
  case dark
}
