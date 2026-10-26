import Foundation
import Testing
@testable import SimulatorImpl

/// 녹화 시작 신호 감지. 실측 stderr 는 `Note: …` 줄 뒤에 `Recording started` 줄이다.
struct RecordingStartDetectorTests {
  private static let note = "Note: No display specified. Defaulting to display: 11111111-2222-3333-4444-555555555555 "
    + "(screenID: 1, name: LCD)\n"

  @Test("한 조각에 Note 줄과 신호 줄이 함께 오면 신호다")
  func signalInOneChunk() {
    var detector = RecordingStartDetector()

    let signaled = detector.feed(Data((Self.note + "Recording started\n").utf8))
    #expect(signaled)
    #expect(detector.sawStart)
  }

  @Test("신호 줄이 두 조각으로 끊겨도 줄이 끝나면 신호다")
  func signalSplitAcrossChunks() {
    var detector = RecordingStartDetector()

    let first = detector.feed(Data((Self.note + "Recording sta").utf8))
    #expect(!first)
    #expect(!detector.sawStart)
    let second = detector.feed(Data("rted\r\n".utf8))
    #expect(second)
  }

  @Test("앞뒤 공백이 붙은 신호 줄도 신호다")
  func trimsWhitespace() {
    var detector = RecordingStartDetector()

    let signaled = detector.feed(Data("  Recording started \n".utf8))
    #expect(signaled)
  }

  @Test("Note 줄만이면 신호가 아니다")
  func noteOnly() {
    var detector = RecordingStartDetector()

    let signaled = detector.feed(Data(Self.note.utf8))
    #expect(!signaled)
    #expect(!detector.sawStart)
  }

  @Test("줄 일부만 같은 다른 줄은 신호가 아니다", arguments: [
    "xRecording started\n", "Recording started.\n", "Recording started later\n", "Recording\n",
  ])
  func partialMatch(line: String) {
    var detector = RecordingStartDetector()

    let signaled = detector.feed(Data(line.utf8))
    #expect(!signaled)
    #expect(!detector.sawStart)
  }

  @Test("줄이 끝나기 전에는 신호로 보지 않는다")
  func waitsForLineEnd() {
    var detector = RecordingStartDetector()

    let first = detector.feed(Data("Recording started".utf8))
    #expect(!first)
    let second = detector.feed(Data("\n".utf8))
    #expect(second)
  }

  @Test("두 번째 신호는 false 이고 sawStart 는 그대로다")
  func secondSignal() {
    var detector = RecordingStartDetector()

    let first = detector.feed(Data("Recording started\n".utf8))
    #expect(first)
    let second = detector.feed(Data("Recording started\n".utf8))
    #expect(!second)
    #expect(detector.sawStart)
  }

  @Test("줄바꿈 없이 상한을 넘게 쌓이면 버리고 다음 줄은 다시 본다")
  func dropsOverlongLine() {
    var detector = RecordingStartDetector()

    let first = detector.feed(Data(String(repeating: "a", count: RecordingStartDetector.maxLineLength + 1).utf8))
    #expect(!first)
    let second = detector.feed(Data("\nRecording started\n".utf8))
    #expect(second)
  }
}
