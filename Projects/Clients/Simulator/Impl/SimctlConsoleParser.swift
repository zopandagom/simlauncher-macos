import Core
import Foundation
import SimulatorInterface

/// `simctl launch --console-pty` 의 stdout 을 앱 줄과 실행 신호로 나누는 순수 값.
/// 앱 줄은 pty 를 거쳐 끝이 `\r\n`(`.crlf`), simctl 자신의 줄은 `\n`(`.lineFeed`) 이다 (측정).
/// - 실행 신호 줄: 신호 줄을 받기 전이고 `.lineFeed` 줄이 정확히 `"<번들 ID>: "` + ASCII 숫자 1자 이상이면 신호다 (한 번만. 넘기지 않는다).
/// - 신호 줄은 앱의 첫 줄들보다 늦게 올 수 있어(콜드 실행에서 약 0.4초, 측정) 앱 줄이 먼저 오면 그 줄 앞에서 `.launched` 를 낸다.
///   그 뒤 온 신호 줄도 넘기지 않는다.
/// - `.lineFeed` 빈 줄은 버린다 (SIGINT 로 끝날 때 simctl 이 찍는다, 측정). 그 밖의 `.lineFeed` 줄(두 번째 신호 모양 줄 포함)과
///   `.crlf`·`.split`·`.endOfStream` 줄은 앱 줄이다.
struct SimctlConsoleParser {
  private let signalPrefix: String
  private var splitter = ConsoleLineSplitter()
  /// `.launched` 를 냈다.
  private(set) var hasLaunched = false
  /// 신호 줄을 받았다 (그 뒤 같은 모양 줄은 앱 줄이다).
  private var sawSignalLine = false

  init(bundleID: AppBundleID) {
    self.signalPrefix = "\(bundleID.rawValue): "
  }

  /// 테스트용: 끊는 길이를 바꾼다.
  init(bundleID: AppBundleID, splitter: ConsoleLineSplitter) {
    self.signalPrefix = "\(bundleID.rawValue): "
    self.splitter = splitter
  }

  /// 조각 하나의 알림, 받은 순서대로 (`[.lines(앞), .launched, .lines(뒤)]`).
  mutating func feed(_ stdout: Data) -> [AppConsoleEvent] {
    self.events(self.splitter.feed(stdout))
  }

  /// 끝날 때 남은 조각을 앱 줄 하나로 낸다.
  mutating func finish() -> [AppConsoleEvent] {
    self.events(self.splitter.finish())
  }

  /// 앱 줄은 첫 줄이 곧 실행 신호라(신호 전이면 그 앞에서 `.launched`) 한 조각의 알림은 `[.launched?, .lines(…)?]` 꼴이다.
  private mutating func events(_ lines: [ConsoleLineSplitter.Line]) -> [AppConsoleEvent] {
    var events: [AppConsoleEvent] = []
    var batch: [String] = []
    for line in lines {
      if line.ending == .lineFeed {
        if line.text.isEmpty {
          continue
        }
        if !self.sawSignalLine, self.isSignal(line.text) {
          self.sawSignalLine = true
          self.markLaunched(&events)
          continue
        }
      }
      self.markLaunched(&events)
      batch.append(line.text)
    }
    if !batch.isEmpty {
      events.append(.lines(batch))
    }
    return events
  }

  private mutating func markLaunched(_ events: inout [AppConsoleEvent]) {
    guard !self.hasLaunched else {
      return
    }
    self.hasLaunched = true
    events.append(.launched)
  }

  private func isSignal(_ text: String) -> Bool {
    guard text.hasPrefix(self.signalPrefix) else {
      return false
    }
    let digits = text.utf8.dropFirst(self.signalPrefix.utf8.count)
    return !digits.isEmpty && digits.allSatisfy { (0x30 ... 0x39).contains($0) }
  }
}
