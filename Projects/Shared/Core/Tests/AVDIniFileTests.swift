import Foundation
import Testing
@testable import Core

struct AVDIniFileTests {
  @Test("key=value(Studio)와 key = value(emulator 가 다시 쓴 형식)를 모두 읽고 앞뒤 공백을 뺀다")
  func bothFormats() throws {
    let data = Data("avd.ini.encoding=UTF-8\nhw.lcd.width = 1080\n  hw.keyboard =   yes  \n".utf8)

    let pairs = try #require(AVDIniFile.parse(data))

    #expect(pairs.map(\.key) == ["avd.ini.encoding", "hw.lcd.width", "hw.keyboard"])
    #expect(pairs.map(\.value) == ["UTF-8", "1080", "yes"])
  }

  @Test("주석(#·;)·빈 줄·= 없는 줄·빈 키는 건너뛴다")
  func skipsLines() throws {
    let data = Data("# comment\n; other\n\n   \nno equals\n=value\na=1\n".utf8)

    let pairs = try #require(AVDIniFile.parse(data))

    #expect(pairs.map(\.key) == ["a"])
    #expect(pairs.map(\.value) == ["1"])
  }

  @Test("같은 키는 처음 값을 쓴다")
  func firstValueWins() throws {
    let pairs = try #require(AVDIniFile.parse(Data("a=1\na=2\n".utf8)))

    #expect(AVDIniFile.value(for: "a", in: pairs) == "1")
    #expect(AVDIniFile.value(for: "b", in: pairs) == nil)
  }

  @Test("CRLF 줄 끝을 읽는다")
  func crlf() throws {
    let pairs = try #require(AVDIniFile.parse(Data("a=1\r\nb = 2\r\n".utf8)))

    #expect(pairs.map(\.key) == ["a", "b"])
    #expect(pairs.map(\.value) == ["1", "2"])
  }

  @Test("값 안의 = 는 그대로 둔다, 빈 값도 읽는다")
  func equalsInValue() throws {
    let pairs = try #require(AVDIniFile.parse(Data("a = x=y = z\nb=\n".utf8)))

    #expect(AVDIniFile.value(for: "a", in: pairs) == "x=y = z")
    #expect(AVDIniFile.value(for: "b", in: pairs)?.isEmpty == true)
  }

  @Test("한글 값을 읽는다")
  func unicodeValue() throws {
    let pairs = try #require(AVDIniFile.parse(Data("avd.ini.displayname=테스트 폰\n".utf8)))

    #expect(AVDIniFile.value(for: "avd.ini.displayname", in: pairs) == "테스트 폰")
  }

  @Test("UTF-8 이 아니면 nil")
  func notUTF8() {
    #expect(AVDIniFile.parse(Data([0x61, 0x3D, 0xFF, 0xFE, 0x0A])) == nil)
  }

  @Test("64 KiB 까지는 읽고, 넘으면 nil")
  func sizeLimit() {
    let line = "a=1\n"
    let atLimit = Data(String(repeating: "x", count: AVDIniFile.maxByteCount - line.utf8.count).utf8) + Data(line.utf8)

    #expect(atLimit.count == 64 * 1024)
    #expect(AVDIniFile.parse(atLimit) != nil)
    #expect(AVDIniFile.parse(atLimit + Data("\n".utf8)) == nil)
  }

  @Test("render 는 순서대로 key=value 줄을 쓰고, 다시 읽으면 같다")
  func renderRoundTrip() throws {
    let pairs: [(key: String, value: String)] = [("z", "1"), ("a", "테스트 폰"), ("m", "x=y")]

    let data = AVDIniFile.render(pairs)
    let parsed = try #require(AVDIniFile.parse(data))

    #expect(String(bytes: data, encoding: .utf8) == "z=1\na=테스트 폰\nm=x=y\n")
    #expect(parsed.map(\.key) == pairs.map(\.key))
    #expect(parsed.map(\.value) == pairs.map(\.value))
  }
}
