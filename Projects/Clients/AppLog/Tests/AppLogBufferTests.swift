import AppLogInterface
import Testing
@testable import AppLogImpl

struct AppLogBufferTests {
  @Test("상한 안에서는 번호 순으로 모두 남는다")
  func keepsLines() {
    var buffer = AppLogBuffer(maxLines: 5, maxBytes: 100)

    #expect(buffer.append(["a", "b"]) == 0)

    #expect(buffer.snapshot() == [AppLogLine(index: 0, text: "a"), AppLogLine(index: 1, text: "b")])
    #expect(buffer.droppedCount == 0)
    #expect(buffer.lastIndex == 1)
  }

  @Test("줄 수 상한으로 앞을 버리고, 여러 번 돌아도(링) 순서가 맞다")
  func ringWraps() {
    var buffer = AppLogBuffer(maxLines: 3, maxBytes: 100)

    #expect(buffer.append(["0", "1", "2", "3"]) == 1)
    #expect(buffer.append(["4", "5", "6"]) == 3)

    #expect(buffer.snapshot().map(\.text) == ["4", "5", "6"])
    #expect(buffer.snapshot().map(\.index) == [4, 5, 6])
    #expect(buffer.droppedCount == 4)
  }

  @Test("바이트 상한으로 앞을 버린 뒤 저장소가 다시 늘어도 순서가 맞다")
  func byteLimitThenGrow() {
    var buffer = AppLogBuffer(maxLines: 10, maxBytes: 4)

    buffer.append(["aa", "bb", "cc"])
    #expect(buffer.snapshot().map(\.text) == ["bb", "cc"])
    buffer.append(["d", "e"])

    #expect(buffer.snapshot().map(\.text) == ["cc", "d", "e"])
    #expect(buffer.byteCount == 4)
    #expect(buffer.droppedCount == 2)
  }

  @Test("바이트 상한보다 긴 줄 하나는 남긴다")
  func keepsSingleLongLine() {
    var buffer = AppLogBuffer(maxLines: 10, maxBytes: 2)

    buffer.append(["a", "longer"])

    #expect(buffer.snapshot().map(\.text) == ["longer"])
  }

  @Test("lines(after:) 는 그 번호 뒤만, 버린 줄은 빼고 돌려준다")
  func linesAfter() {
    var buffer = AppLogBuffer(maxLines: 3, maxBytes: 100)
    buffer.append(["0", "1", "2", "3", "4"])

    #expect(buffer.lines(after: 3).map(\.text) == ["4"])
    #expect(buffer.lines(after: 0).map(\.text) == ["2", "3", "4"])
    #expect(buffer.lines(after: 4).isEmpty)
  }
}
