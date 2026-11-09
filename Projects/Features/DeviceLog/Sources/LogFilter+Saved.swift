import Core
import Foundation

/// 편집용 `LogFilter` 와 저장 값 `SavedLogFilter`(Core) 사이의 변환. 불러오기(`LogFilter.load(_:)`)는 조건 id 를 다루므로
/// `LogFilter.swift` 에 둔다.
extension LogFilter.Kind {
  init(_ saved: SavedLogFilter.Kind) {
    switch saved {
    case .contains: self = .contains
    case .prefix: self = .prefix
    case .regex: self = .regex
    }
  }

  var saved: SavedLogFilter.Kind {
    switch self {
    case .contains: .contains
    case .prefix: .prefix
    case .regex: .regex
    }
  }
}

extension LogFilter {
  /// 저장할 조건: 글자가 빈 조건을 빼고 순서대로 (거르기 규칙 "빈 조건은 뺀다" 와 같다).
  func savedConditions() -> [SavedLogFilter.Condition] {
    self.conditions
      .filter { !$0.text.isEmpty }
      .map { SavedLogFilter.Condition(kind: $0.kind.saved, text: $0.text, isExcluded: $0.isExcluded) }
  }
}
