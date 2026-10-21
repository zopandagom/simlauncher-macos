/// 저장된 카탈로그 주소 한 줄의 상태.
public struct CatalogURLEntry: Hashable, Sendable {
  public enum Status: Hashable, Sendable {
    /// 쓸 수 있다.
    case usable(DownloadURL)
    /// 주소 검사에 걸렸다 (관리자가 미리 넣은 http 주소 등).
    case invalid(DownloadURLProblem)
    /// 앞(`firstIndex`, 0부터)의 항목과 같은 카탈로그다(`DownloadURL.comparisonKey`). 한 번만 읽는다.
    case duplicate(firstIndex: Int)
  }

  /// 저장된 문자열 그대로 (화면에 보이고, 삭제할 때 열쇠로 쓴다).
  public let raw: String
  public let status: Status

  public init(raw: String, status: Status) {
    self.raw = raw
    self.status = status
  }
}

/// 저장된 카탈로그 주소 목록의 규칙. 저장된 값은 형식 검사 없이 들어올 수 있다 (관리자가 `defaults write` 로 미리 넣은 값).
public enum CatalogURLList {
  /// 저장 순서대로 상태를 매긴다. 같은 카탈로그가 여러 번 있으면 처음 것만 `usable`, 뒤는 `duplicate(firstIndex: 처음 인덱스)`.
  /// 주소 검사에 걸린 항목은 중복으로 보지 않는다.
  public static func entries(_ raws: [String]) -> [CatalogURLEntry] {
    var firstIndexByKey: [String: Int] = [:]
    var entries: [CatalogURLEntry] = []
    entries.reserveCapacity(raws.count)
    for (index, raw) in raws.enumerated() {
      guard let url = DownloadURL(raw) else {
        // `DownloadURL(_:)` 이 nil 이면 `problem(in:)` 은 nil 이 아니다 (같은 판정).
        entries.append(CatalogURLEntry(raw: raw, status: .invalid(DownloadURL.problem(in: raw) ?? .malformed)))
        continue
      }
      let key = url.comparisonKey
      if let first = firstIndexByKey[key] {
        entries.append(CatalogURLEntry(raw: raw, status: .duplicate(firstIndex: first)))
      } else {
        firstIndexByKey[key] = index
        entries.append(CatalogURLEntry(raw: raw, status: .usable(url)))
      }
    }
    return entries
  }

  /// `url` 과 같은 카탈로그인 첫 항목의 인덱스. 없으면 nil. 주소 검사에 걸리는 항목은 비교하지 않는다.
  public static func indexOfSameCatalog(as url: DownloadURL, in raws: [String]) -> Int? {
    let key = url.comparisonKey
    return raws.firstIndex { raw in
      DownloadURL(raw)?.comparisonKey == key
    }
  }

  /// 새로 저장할 문자열: 앞뒤 공백을 빼고 퍼센트 인코딩된 `url.url.absoluteString`. 다시 `DownloadURL` 로 읽으면 같은 URL 이다.
  public static func storedString(for url: DownloadURL) -> String {
    url.url.absoluteString
  }
}
