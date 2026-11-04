import Core
import Foundation
import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// 콘솔 stdout 해석. 앱 줄은 `\r\n`, simctl 의 신호 줄과 끝 빈 줄은 `\n` (측정).
struct SimctlConsoleParserTests {
  private static let bundleID = AppBundleID("dev.simlauncher.logprobe")!

  private static func parser() -> SimctlConsoleParser {
    SimctlConsoleParser(bundleID: self.bundleID)
  }

  @Test("LF 신호 줄은 .launched 한 번이고 넘기지 않는다, 뒤 앱 줄은 넘긴다")
  func signalLine() {
    var parser = Self.parser()

    #expect(parser.feed(Data("dev.simlauncher.logprobe: 90395\n".utf8)) == [.launched])
    #expect(parser.feed(Data("tick 1\r\n".utf8)) == [.lines(["tick 1"])])
    #expect(parser.hasLaunched)
  }

  @Test("같은 글자의 CRLF 줄은 앱 줄이다 (그 줄에서 .launched)")
  func crlfLookalikeIsAppLine() {
    var parser = Self.parser()

    #expect(parser.feed(Data("dev.simlauncher.logprobe: 1\r\n".utf8)) == [
      .launched, .lines(["dev.simlauncher.logprobe: 1"]),
    ])
  }

  @Test(
    "번들 ID 가 다르거나 숫자가 아닌 LF 줄은 앱 줄",
    arguments: [
      "com.other.app: 1",
      "dev.simlauncher.logprobe: x1",
      "dev.simlauncher.logprobe: ",
      "dev.simlauncher.logprobe:1"
    ]
  )
  func otherLFLinesAreAppLines(text: String) {
    var parser = Self.parser()

    #expect(parser.feed(Data("\(text)\n".utf8)) == [.launched, .lines([text])])
  }

  @Test("앱 줄이 신호 줄보다 먼저면 그 앞에서 .launched, 뒤에 온 신호 줄은 넘기지 않는다")
  func appLineBeforeSignal() {
    var parser = Self.parser()

    #expect(parser.feed(Data("probe start\r\n".utf8)) == [.launched, .lines(["probe start"])])
    #expect(parser.feed(Data("dev.simlauncher.logprobe: 82449\n".utf8)).isEmpty)
    #expect(parser.feed(Data("tick 1\r\n".utf8)) == [.lines(["tick 1"])])
  }

  @Test("한 조각 안의 순서: 앱 줄 · 신호 · 앱 줄 → [.launched, .lines(둘)]")
  func orderWithinChunk() {
    var parser = Self.parser()

    let events = parser.feed(Data("a\r\ndev.simlauncher.logprobe: 7\nb\r\n".utf8))

    #expect(events == [.launched, .lines(["a", "b"])])
  }

  @Test("두 번째 신호 모양 LF 줄은 앱 줄이다")
  func secondSignalLookalike() {
    var parser = Self.parser()

    #expect(parser.feed(Data("dev.simlauncher.logprobe: 1\n".utf8)) == [.launched])
    #expect(parser.feed(Data("dev.simlauncher.logprobe: 2\n".utf8)) == [.lines(["dev.simlauncher.logprobe: 2"])])
  }

  @Test("끝의 빈 LF 줄은 버리고, CRLF 빈 줄(앱의 빈 print)은 넘긴다")
  func emptyLines() {
    var parser = Self.parser()

    #expect(parser.feed(Data("dev.simlauncher.logprobe: 1\n\r\n\n".utf8)) == [.launched, .lines([""])])
  }

  @Test("finish() 는 남은 조각을 앱 줄 하나로 낸다")
  func finishEmitsRemainder() {
    var parser = Self.parser()

    #expect(parser.feed(Data("dev.simlauncher.logprobe: 1\npartial".utf8)) == [.launched])
    #expect(parser.finish() == [.lines(["partial"])])
    #expect(parser.finish().isEmpty)
  }
}
