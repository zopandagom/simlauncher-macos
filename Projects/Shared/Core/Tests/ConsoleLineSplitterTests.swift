import Foundation
import Testing
@testable import Core

struct ConsoleLineSplitterTests {
  private typealias Line = ConsoleLineSplitter.Line

  @Test("\\r\\n 은 .crlf 이고 텍스트에 \\r 이 없다, \\n 만이면 .lineFeed")
  func endings() {
    var splitter = ConsoleLineSplitter()

    let lines = splitter.feed(Data("app line\r\ncom.example.app: 42\n".utf8))

    #expect(lines == [Line(text: "app line", ending: .crlf), Line(text: "com.example.app: 42", ending: .lineFeed)])
    #expect(splitter.finish().isEmpty)
  }

  @Test("빈 줄도 줄이다 (\\r\\n 빈 줄은 .crlf, \\n 빈 줄은 .lineFeed)")
  func emptyLines() {
    var splitter = ConsoleLineSplitter()

    #expect(splitter.feed(Data("\r\n\n".utf8)) == [Line(text: "", ending: .crlf), Line(text: "", ending: .lineFeed)])
  }

  @Test("조각 경계가 줄 가운데면 다음 조각과 이어 붙인다")
  func chunkBoundaryInsideLine() {
    var splitter = ConsoleLineSplitter()

    #expect(splitter.feed(Data("tic".utf8)).isEmpty)
    #expect(splitter.feed(Data("k 1\r\ntick".utf8)) == [Line(text: "tick 1", ending: .crlf)])
    #expect(splitter.feed(Data(" 2\r\n".utf8)) == [Line(text: "tick 2", ending: .crlf)])
  }

  @Test("조각 경계가 \\r 과 \\n 사이여도 .crlf")
  func chunkBoundaryBetweenCRAndLF() {
    var splitter = ConsoleLineSplitter()

    #expect(splitter.feed(Data("a\r".utf8)).isEmpty)
    #expect(splitter.feed(Data("\n".utf8)) == [Line(text: "a", ending: .crlf)])
  }

  @Test("조각 경계가 UTF-8 글자 가운데여도 깨지지 않는다")
  func chunkBoundaryInsideCharacter() {
    var splitter = ConsoleLineSplitter()
    let bytes = Array("한글\r\n".utf8)

    #expect(splitter.feed(Data(bytes[..<2])).isEmpty)
    #expect(splitter.feed(Data(bytes[2...])) == [Line(text: "한글", ending: .crlf)])
  }

  @Test("잘못된 UTF-8 바이트는 U+FFFD 로 읽는다")
  func invalidUTF8() {
    var splitter = ConsoleLineSplitter()

    #expect(splitter.feed(Data([0x61, 0xFF, 0x62, 0x0A])) == [Line(text: "a\u{FFFD}b", ending: .lineFeed)])
  }

  @Test("줄바꿈 없이 길면 글자 경계로 물러나 .split 으로 끊고 나머지는 이어진다")
  func splitsLongLine() {
    var splitter = ConsoleLineSplitter(maxLineBytes: 4)

    // "ab한c" = 61 62 ED 95 9C 63: 4바이트 자리가 '한' 가운데라 "ab" 에서 끊는다.
    let lines = splitter.feed(Data("ab한cd\r\n".utf8))

    #expect(lines == [
      Line(text: "ab", ending: .split),
      Line(text: "한c", ending: .split),
      Line(text: "d", ending: .crlf),
    ])
  }

  @Test("한 조각에 긴 출력이 오면 여러 .split 줄, 끝의 남은 조각은 finish() 가 .endOfStream 으로")
  func splitsAcrossChunksAndFinishes() {
    var splitter = ConsoleLineSplitter(maxLineBytes: 3)

    #expect(splitter.feed(Data("abcdefg".utf8)) == [
      Line(text: "abc", ending: .split),
      Line(text: "def", ending: .split),
    ])
    #expect(splitter.feed(Data("h".utf8)).isEmpty)
    #expect(splitter.finish() == [Line(text: "gh", ending: .endOfStream)])
    #expect(splitter.finish().isEmpty)
  }

  @Test("maxLineBytes 꼭 맞는 줄 뒤의 \\r\\n 은 끊지 않고 .crlf")
  func exactLengthLineWithCRLF() {
    var splitter = ConsoleLineSplitter(maxLineBytes: 3)

    #expect(splitter.feed(Data("abc\r".utf8)).isEmpty)
    #expect(splitter.feed(Data("\n".utf8)) == [Line(text: "abc", ending: .crlf)])
  }

  @Test("기본 상한은 16 KiB")
  func defaultLimit() {
    var splitter = ConsoleLineSplitter()
    let long = String(repeating: "x", count: ConsoleLineSplitter.maxLineBytes + 10)

    let lines = splitter.feed(Data(long.utf8))

    #expect(ConsoleLineSplitter.maxLineBytes == 16 * 1024)
    #expect(lines == [Line(text: String(repeating: "x", count: 16 * 1024), ending: .split)])
    #expect(splitter.finish() == [Line(text: String(repeating: "x", count: 10), ending: .endOfStream)])
  }
}
