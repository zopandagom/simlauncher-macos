/// 저장된 빌드 카탈로그 주소 목록과 잠금 여부.
public struct CatalogURLSetting: Hashable, Sendable {
  /// 빈 목록, 잠기지 않음.
  public static let empty = CatalogURLSetting(urls: [], isLocked: false)

  /// 저장된 문자열 그대로, 저장 순서. 형식 검사는 하지 않는다 (Core `CatalogURLList.entries`).
  public let urls: [String]
  /// 관리자가 이 키를 강제했다 (`objectIsForced`). 목록 전체를 바꿀 수 없다.
  public let isLocked: Bool

  public init(urls: [String], isLocked: Bool) {
    self.urls = urls
    self.isLocked = isLocked
  }
}
