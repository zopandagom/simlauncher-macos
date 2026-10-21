import Foundation

public extension BuildCatalog {
  /// `init(jsonData:)` 와 같다. 5 MiB 에서 약 0.3초 걸리므로 부른 액터(메인)를 막지 않게 `@concurrent` 로 메인 밖에서 돈다.
  /// Model 이 `Task.detached` 없이 메인 밖에서 해석하는 진입점이다 (CONVENTIONS §2). 취소를 보지 않는다
  /// (해석은 중간에 멈추지 않으므로 부른 쪽이 끝난 뒤 확인한다).
  @concurrent
  static func decoded(from data: Data) async throws(BuildCatalogProblem) -> BuildCatalog {
    try BuildCatalog(jsonData: data)
  }
}
