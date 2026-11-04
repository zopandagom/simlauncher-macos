import AppLogInterface
import Foundation

/// 줄 맞춤에 쓰는 필터 (`LogFilter.compiled()`). 모든 조건을 `NSRegularExpression` 으로 맞춘다: 포함·시작은 글자를
/// `escapedPattern` 으로, 정규식은 그대로. 5만 줄에서 `String.range(of:options:)` 나 Swift `Regex` 보다 빨랐다
/// (대소문자 무시 포함 55ms, 포함 3개 + 제외 1개 119ms, Swift `Regex` 285ms. 2026-11-03 실측, `-O`).
/// 사용자 정규식은 느릴 수 있어 줄 맞춤과 강조 범위 계산은 모두 메인 밖 진입점 `filtered(_:by:)` 안에서 하고(맞춤 함수는 private),
/// 결과를 보이는 줄(`VisibleLogLine`)에 담아 넘긴다. 표는 받은 범위만 칠한다. 시간 제한은 두지 않고, 취소하면 맞춤 중에도 멈춘다.
/// 맞은 줄은 강조할 곳을 끝까지 모으므로 첫 맞춤에서 멈출 때보다 느리다: Example 의 5만 줄(전부 맞음)에서 포함 `line` 94ms,
/// 정규식 `.`(글자마다 맞음, 조건당 맞춤 `matchLimit` 번까지) 384ms, 95줄만 맞는 포함 69ms (2026-11-04 실측, `-O`).
public struct CompiledLogFilter: Sendable {
  struct Matcher: Sendable {
    let regex: NSRegularExpression
    /// 머리말 뒤 메시지 시작에 붙여(`.anchored`) 맞춘다.
    let isPrefix: Bool
  }

  /// 한 줄에 강조하는 곳의 최대 수 (합친 뒤). 5만 줄이 모두 이만큼이어도 창 하나에 약 27 MB.
  static let highlightLimit = 64
  /// 조건 하나가 한 줄에서 받는 맞춤의 최대 수. `.` 처럼 글자마다 맞는 정규식도 긴 줄에서 이만큼만 훑는다
  /// (보임·숨김은 첫 맞춤으로 정해지므로 바뀌지 않고, 강조만 앞쪽까지다).
  static let matchLimit = 1024

  let includes: [Matcher]
  let excludes: [Matcher]

  /// 조건이 없다 (모든 줄이 보인다).
  var isEmpty: Bool {
    self.includes.isEmpty && self.excludes.isEmpty
  }

  /// 맞는 줄만 순서대로, 줄마다 강조할 곳과 함께. 맞춤과 강조 계산은 모두 여기(메인 밖)에서 하고, 줄을 맞추는 다른 진입점은 없다.
  /// 1024줄마다, 그리고 한 줄을 맞추는 중에도(`.reportProgress`) 취소를 확인하고, 취소되면 그때까지 거른 것을 돌려준다 (부른 쪽이 버린다).
  /// 필터가 없으면(nil 이거나 조건 없음) 모든 줄을 강조 없이 돌려준다.
  @concurrent
  nonisolated static func filtered(_ lines: [AppLogLine], by filter: CompiledLogFilter?) async -> [VisibleLogLine] {
    guard let filter, !filter.isEmpty else {
      return lines.map { VisibleLogLine(line: $0, highlights: []) }
    }
    var result: [VisibleLogLine] = []
    var isCancelled = false
    for (offset, line) in lines.enumerated() {
      if offset % 1024 == 1023, Task.isCancelled {
        break
      }
      if let highlights = filter.evaluate(line.text, isCancelled: &isCancelled) {
        result.append(VisibleLogLine(line: line, highlights: highlights))
      }
      if isCancelled {
        break
      }
    }
    return result
  }

  /// 줄 하나를 맞춘다: 숨기면 nil, 보이면 강조할 곳. 제외가 하나라도 맞으면 숨기고, 포함이 없으면 강조 없이 보이고, 있으면 하나라도
  /// 맞아야 보인다(빈 범위 맞음도 맞음, 강조는 안 함). 강조는 포함 조건마다 맞은 곳(시작은 메시지 처음 한 곳, 그 밖은 앞에서부터
  /// 맞춤 `matchLimit` 번까지)을 모아 합친 앞 `highlightLimit` 곳. 맞추는 중에 취소되면 `isCancelled` 를 세우고 nil.
  private func evaluate(_ text: String, isCancelled: inout Bool) -> [LogHighlight]? {
    var subject = Subject(text: text)
    for matcher in self.excludes {
      var isExcluded = false
      Self.enumerate(matcher, in: &subject, isCancelled: &isCancelled) { _ in
        isExcluded = true
        return false
      }
      if isCancelled || isExcluded {
        return nil
      }
    }
    guard !self.includes.isEmpty else { return [] }
    var isMatched = false
    var ranges: [NSRange] = []
    for matcher in self.includes {
      // 한 조건의 맞은 곳은 앞에서부터 겹치지 않고 오므로 붙은 곳만 바로 합친다 (`.` 은 긴 줄에서도 한 곳).
      var merged: [NSRange] = []
      var count = 0
      Self.enumerate(matcher, in: &subject, isCancelled: &isCancelled) { range in
        isMatched = true
        count += 1
        if range.length > 0 {
          if let last = merged.last, last.upperBound >= range.location {
            merged[merged.count - 1].length = max(last.upperBound, range.upperBound) - last.location
          } else if merged.count < Self.highlightLimit {
            merged.append(range)
          } else {
            return false
          }
        }
        return count < Self.matchLimit
      }
      if isCancelled {
        return nil
      }
      ranges += merged
    }
    guard isMatched else { return nil }
    return Self.merge(ranges).prefix(Self.highlightLimit).map(LogHighlight.init)
  }

  /// 위치 순으로 놓고 겹치거나 붙은 곳을 합친다.
  private static func merge(_ ranges: [NSRange]) -> [NSRange] {
    var merged: [NSRange] = []
    for range in ranges.sorted(by: { $0.location < $1.location }) {
      if let last = merged.last, last.upperBound >= range.location {
        merged[merged.count - 1].length = max(last.upperBound, range.upperBound) - last.location
      } else {
        merged.append(range)
      }
    }
    return merged
  }

  /// 조건의 맞은 곳을 앞에서부터 `body` 에 넘긴다 (`body` 가 거짓이면 멈춘다). 시작 조건은 메시지 처음에 붙여 한 곳만.
  /// 맞춤 중 진행 알림(`.reportProgress`, 되추적 중에도 온다)마다 취소를 보고, 취소되면 멈추고 `isCancelled` 를 세운다:
  /// 끝나지 않는 정규식(`(a+)+$` 와 긴 `a…b` 줄)도 취소하면 협력 스레드를 놓는다 (`a` × 27 + `b`: 취소 없이 4.7초,
  /// 0.1초 뒤 취소하면 0.107초에 돌아옴, 진행 알림은 약 86µs 마다. 2026-11-04 실측, `-O`).
  private static func enumerate(
    _ matcher: Matcher,
    in subject: inout Subject,
    isCancelled: inout Bool,
    _ body: (NSRange) -> Bool
  ) {
    var options: NSRegularExpression.MatchingOptions = [.reportProgress]
    var range = NSRange(location: 0, length: subject.length)
    if matcher.isPrefix {
      let location = subject.messageStart()
      range = NSRange(location: location, length: subject.length - location)
      options.insert(.anchored)
    }
    var cancelled = false
    matcher.regex.enumerateMatches(in: subject.text, options: options, range: range) { result, _, stop in
      if Task.isCancelled {
        cancelled = true
        stop.pointee = true
        return
      }
      // 진행 알림은 result 가 nil 이다 (맞춤이 아니다).
      guard let result else { return }
      if !body(result.range) || matcher.isPrefix {
        stop.pointee = true
      }
    }
    if cancelled {
      isCancelled = true
    }
  }

  /// 맞추는 줄과 그 길이(UTF-16), 메시지 시작 위치 (시작 조건이 있을 때 한 번만 찾는다).
  private struct Subject {
    let text: String
    let length: Int
    private var cachedMessageStart: Int?

    init(text: String) {
      self.text = text
      self.length = (text as NSString).length
    }

    mutating func messageStart() -> Int {
      if let cachedMessageStart {
        return cachedMessageStart
      }
      let offset = LogLineHeader.messageOffset(in: self.text)
      self.cachedMessageStart = offset
      return offset
    }
  }
}
