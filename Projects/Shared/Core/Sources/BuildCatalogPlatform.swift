/// 카탈로그 앱의 플랫폼 (docs/CATALOG.md "platform"). rawValue 는 JSON 값이고 소문자 정확히 일치만 받는다.
/// schemaVersion 1 카탈로그의 앱은 모두 `.ios` 다.
public enum BuildCatalogPlatform: String, Hashable, Sendable, CaseIterable {
  case ios, android
}
