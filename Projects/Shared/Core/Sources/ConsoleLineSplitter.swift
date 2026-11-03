import Foundation

/// 받은 바이트 조각을 줄로 나누는 순수 값. 조각은 줄 경계와 맞지 않는다 (한 번에 여러 줄이 오거나 줄 일부만 온다, 측정).
/// `\n`(0x0A) 에서 바이트로 먼저 나눈 뒤 줄마다 UTF-8 로 읽는다 (잘못된 바이트는 U+FFFD). 그래서 조각 경계가 글자 가운데여도 깨지지 않는다.
/// 시뮬레이터 앱 콘솔(pty)은 줄 끝이 `\r\n`, simctl 자신의 줄은 `\n` 이라 끝을 `Ending` 으로 구별해 넘긴다.
public struct ConsoleLineSplitter: Sendable {
  /// 줄이 끝난 방식.
  public enum Ending: Hashable, Sendable {
    /// `\r\n` (텍스트에 `\r` 은 없다).
    case crlf
    /// `\r` 없는 `\n`.
    case lineFeed
    /// 줄바꿈 없이 `maxLineBytes` 를 넘어 끊었다. 다음 줄이 이어진다.
    case split
    /// 흐름이 끝날 때 줄바꿈 없이 남은 조각 (`finish()`).
    case endOfStream
  }

  public struct Line: Hashable, Sendable {
    public let text: String
    public let ending: Ending

    public init(text: String, ending: Ending) {
      self.text = text
      self.ending = ending
    }
  }

  /// 줄바꿈 없이 이보다 길면 끊어 `.split` 줄로 낸다 (UTF-8 글자 경계로 물러나 자른다). 줄바꿈 없는 긴 출력이 메모리를 키우지 않게 한다.
  public static let maxLineBytes = 16 * 1024

  private static let newline: UInt8 = 0x0A
  private static let carriageReturn: UInt8 = 0x0D

  private let maxLineBytes: Int
  /// 아직 줄바꿈을 받지 못한 바이트.
  private var pending: [UInt8] = []

  public init() {
    self.maxLineBytes = Self.maxLineBytes
  }

  /// 테스트용: 끊는 길이를 바꾼다 (1 이상).
  init(maxLineBytes: Int) {
    self.maxLineBytes = max(1, maxLineBytes)
  }

  /// 조각을 더하고 다 된 줄을 받은 순서대로 돌려준다. 바로 앞이 `\r` 이면 빼고 `.crlf`.
  public mutating func feed(_ data: Data) -> [Line] {
    guard !data.isEmpty else {
      return []
    }
    self.pending.append(contentsOf: data)
    var lines: [Line] = []
    var start = 0
    let end = self.pending.count
    var cursor = start
    while cursor < end {
      if self.pending[cursor] == Self.newline {
        var contentEnd = cursor
        var ending = Ending.lineFeed
        if contentEnd > start, self.pending[contentEnd - 1] == Self.carriageReturn {
          contentEnd -= 1
          ending = .crlf
        }
        start = self.appendSplitPieces(from: start, to: contentEnd, into: &lines)
        lines.append(Line(text: self.text(start ..< contentEnd), ending: ending))
        cursor += 1
        start = cursor
      } else if cursor - start + 1 > self.maxLineBytes, self.pending[cursor] != Self.carriageReturn {
        // 줄바꿈 없이 maxLineBytes 를 넘었다: 앞을 끊어 낸다. `\r` 은 바로 뒤 `\n` 과 함께 줄 끝일 수 있어 한 바이트 기다린다.
        start = self.appendSplitPieces(from: start, to: cursor + 1, into: &lines)
        cursor += 1
      } else {
        cursor += 1
      }
    }
    self.pending.removeFirst(start)
    return lines
  }

  /// 남은 바이트(줄바꿈 없음)를 `.endOfStream` 줄 하나로 돌려주고 비운다. 비었으면 [].
  public mutating func finish() -> [Line] {
    guard !self.pending.isEmpty else {
      return []
    }
    let line = Line(text: self.text(0 ..< self.pending.count), ending: .endOfStream)
    self.pending = []
    return [line]
  }

  /// `start..<end` 가 `maxLineBytes` 보다 길면 앞에서부터 `.split` 줄로 끊어 넣고, 남은 시작 위치를 돌려준다.
  /// 끊는 자리는 UTF-8 이어지는 바이트(10xxxxxx)가 아닐 때까지 물러난다 (글자 하나가 통째로 길면 그냥 자른다).
  private func appendSplitPieces(from start: Int, to end: Int, into lines: inout [Line]) -> Int {
    var start = start
    while end - start > self.maxLineBytes {
      var cut = start + self.maxLineBytes
      while cut > start, self.pending[cut] & 0xC0 == 0x80 {
        cut -= 1
      }
      if cut == start {
        cut = start + self.maxLineBytes
      }
      lines.append(Line(text: self.text(start ..< cut), ending: .split))
      start = cut
    }
    return start
  }

  /// 잘못된 UTF-8 은 U+FFFD 로 고쳐 읽는다 (이 초기화는 받은 바이트를 고쳐 쓴다). 실패하는(nil) 읽기는 줄을 잃으므로 쓰지 않는다.
  private func text(_ range: Range<Int>) -> String {
    String(unsafeUninitializedCapacity: range.count) { buffer in
      _ = buffer.initialize(fromContentsOf: self.pending[range])
      return range.count
    }
  }
}
