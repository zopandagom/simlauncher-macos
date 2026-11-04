import AppLogInterface
import Foundation

/// 필터를 지나 표에 보이는 줄과 그 줄에서 강조할 곳. 거르기(메인 밖, `CompiledLogFilter.filtered`)가 만들고, 표는 받은 범위만 칠한다.
public struct VisibleLogLine: Hashable, Sendable {
  public let line: AppLogLine
  /// 위치 순이고, 겹치거나 붙은 곳은 합쳤다. 한 줄에 최대 `CompiledLogFilter.highlightLimit` 곳.
  public let highlights: [LogHighlight]

  public init(line: AppLogLine, highlights: [LogHighlight]) {
    self.line = line
    self.highlights = highlights
  }

  public var index: Int {
    self.line.index
  }
}

/// 강조할 곳의 UTF-16 범위 (`NSRange` 의 절반 크기. 줄은 Client 가 16 KiB 에서 끊으므로 `Int32` 로 충분하다).
public struct LogHighlight: Hashable, Sendable {
  public let location: Int32
  public let length: Int32

  public init(location: Int32, length: Int32) {
    self.location = location
    self.length = length
  }

  init(_ range: NSRange) {
    self.init(location: Int32(clamping: range.location), length: Int32(clamping: range.length))
  }

  var nsRange: NSRange {
    NSRange(location: Int(self.location), length: Int(self.length))
  }
}
