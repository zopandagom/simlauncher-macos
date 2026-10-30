import Foundation

/// 심볼릭 링크를 끝까지 푼 실제 경로 (`realpath(3)`). 대상이 없거나 루프면 nil.
/// AppBundle Impl 의 `RealPath` 를 복제했다 (Impl 끼리 import 할 수 없다).
enum RealPath {
  static func of(_ url: URL) -> String? {
    guard let resolved = realpath(url.path(percentEncoded: false), nil) else {
      return nil
    }
    defer { free(resolved) }
    return String(cString: resolved)
  }
}
