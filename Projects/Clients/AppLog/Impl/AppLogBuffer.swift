import AppLogInterface

/// 세션 하나의 최근 줄 (순수). 줄 수 상한·바이트(UTF-8) 상한 중 먼저 닿는 쪽으로 앞을 버린다.
/// 고정 용량 링(머리 위치 + 배열)이라 앞 버림이 원소 이동 없이 버린 수만큼만 든다.
struct AppLogBuffer {
  private let maxLines: Int
  private let maxBytes: Int
  /// 링 저장소. 크기는 처음부터 잡지 않고 `maxLines` 까지 는다. 버린 칸은 빈 문자열로 비워 메모리를 놓는다.
  private var storage: [String] = []
  private var head = 0
  private(set) var count = 0
  private(set) var byteCount = 0
  /// 다음 줄의 번호 (지금까지 받은 줄 수).
  private(set) var nextIndex = 0

  init(maxLines: Int, maxBytes: Int) {
    self.maxLines = max(1, maxLines)
    self.maxBytes = max(1, maxBytes)
  }

  /// 지금까지 버린 앞 줄 수. 번호가 이보다 작은 줄은 없다.
  var droppedCount: Int {
    self.nextIndex - self.count
  }

  /// 마지막 줄 번호. 없으면 `droppedCount - 1`.
  var lastIndex: Int {
    self.nextIndex - 1
  }

  /// 줄을 더하고 이번에 버린 앞 줄 수를 돌려준다. 바이트 상한보다 긴 줄 하나만 남으면 그 줄은 둔다 (줄은 16 KiB 에서 이미 끊겼다).
  @discardableResult
  mutating func append(_ texts: [String]) -> Int {
    var dropped = 0
    for text in texts {
      if self.count == self.maxLines {
        self.dropFirst()
        dropped += 1
      }
      self.push(text)
      while self.byteCount > self.maxBytes, self.count > 1 {
        self.dropFirst()
        dropped += 1
      }
    }
    return dropped
  }

  /// 지금 버퍼의 모든 줄, 번호 순.
  func snapshot() -> [AppLogLine] {
    self.lines(after: self.droppedCount - 1)
  }

  /// 번호가 `index` 보다 큰 줄, 번호 순 (버린 줄은 빠진다).
  func lines(after index: Int) -> [AppLogLine] {
    let first = max(index + 1, self.droppedCount)
    guard first < self.nextIndex else {
      return []
    }
    var lines: [AppLogLine] = []
    lines.reserveCapacity(self.nextIndex - first)
    for lineIndex in first ..< self.nextIndex {
      let offset = lineIndex - self.droppedCount
      lines.append(AppLogLine(index: lineIndex, text: self.storage[(self.head + offset) % self.storage.count]))
    }
    return lines
  }

  private mutating func push(_ text: String) {
    if self.count == self.storage.count {
      // 저장소가 다 찼고 아직 maxLines 보다 작다: 순서를 맞춘 뒤 늘린다 (바이트 상한으로 앞을 버린 뒤에만 head 가 0 이 아니다).
      if self.head != 0 {
        self.storage = Array(self.storage[self.head...] + self.storage[..<self.head])
        self.head = 0
      }
      self.storage.append(text)
    } else {
      self.storage[(self.head + self.count) % self.storage.count] = text
    }
    self.count += 1
    self.nextIndex += 1
    self.byteCount += text.utf8.count
  }

  private mutating func dropFirst() {
    self.byteCount -= self.storage[self.head].utf8.count
    self.storage[self.head] = ""
    self.head = (self.head + 1) % self.storage.count
    self.count -= 1
  }
}
