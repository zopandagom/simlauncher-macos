import Foundation

/// 저장된 `CatalogURLs` 값 해석. 관리자가 `defaults write` 로 넣은 값은 형식이 다를 수 있다.
enum CatalogURLValue {
  /// - 배열이면 문자열 항목만 순서대로 (앞뒤 공백·빈 문자열 그대로). 숫자·사전 같은 항목은 뺀다.
  /// - 문자열 하나면 한 항목 목록 (관리자가 `-array` 를 빠뜨린 경우).
  /// - 그 밖(nil·숫자·Data·사전)은 빈 목록.
  static func strings(from value: Any?) -> [String] {
    if let array = value as? [Any] {
      return array.compactMap { $0 as? String }
    }
    if let string = value as? String {
      return [string]
    }
    return []
  }
}
