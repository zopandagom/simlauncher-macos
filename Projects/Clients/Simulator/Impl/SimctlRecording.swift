import Foundation
import SimulatorInterface

/// `simctl io recordVideo` 의 stderr 조각에서 시작 신호(`Recording started` 줄)를 찾는다 (순수).
/// 실측(Xcode 27.1): 첫 화면을 처리하면 stderr 에 `Recording started` 한 줄을 찍는다. 그 앞에 `Note: No display specified…` 줄이 온다.
/// 앞뒤 공백·`\r` 을 뺀 줄 전체가 같아야 한다 (줄 일부만 같은 줄은 아니다). 조각이 줄 중간에서 끊겨도 이어 붙여 본다.
/// stdout(`Wrote video to: <경로>`, 기기 이름이 섞인다)은 넣지 않는다.
struct RecordingStartDetector {
  static let signal = "Recording started"
  /// 줄바꿈 없이 이보다 길게 쌓이면 앞을 버린다 (신호 줄은 짧다).
  static let maxLineLength = 4096

  private var buffer = Data()
  /// 시작 신호를 봤다.
  private(set) var sawStart = false

  /// 조각을 받아, 이 조각에서 **처음** 신호 줄을 봤으면 true. 이미 봤으면 늘 false 이고 더 쌓지 않는다.
  mutating func feed(_ data: Data) -> Bool {
    guard !self.sawStart else { return false }
    self.buffer.append(data)
    // 바이트에서 `\n` 으로 먼저 자른 뒤 디코딩한다 (조각 경계가 UTF-8 글자 가운데여도 깨지지 않는다).
    while let newline = self.buffer.firstIndex(of: UInt8(ascii: "\n")) {
      let line = self.buffer[self.buffer.startIndex ..< newline]
      self.buffer = Data(self.buffer[self.buffer.index(after: newline)...])
      if Self.isSignal(line) {
        self.sawStart = true
        self.buffer = Data()
        return true
      }
    }
    if self.buffer.count > Self.maxLineLength {
      self.buffer = Data()
    }
    return false
  }

  private static func isSignal(_ line: Data) -> Bool {
    String(bytes: line, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == self.signal
  }
}

/// 끝난 녹화의 결과 판정 (순수). 종료 코드 대신 "시작 신호를 받았는가 + 끝난 뒤 파일 크기"로 정한다.
/// 0바이트 파일은 저장 성공으로 보지 않고(꺼진 기기·SIGTERM 뒤, 측정), 화면이 담긴 파일(크기 > 0)은 어떻게 끝났든 버리지 않는다.
enum SimctlRecordingOutcome {
  /// 명령이 끝난 방식.
  enum Ending: Hashable, Sendable {
    /// 호출한 Task 취소로 멈췄다 (`CommandError.cancelled`).
    case stopped
    /// 스스로 끝났다.
    case exited(code: Int32, stderr: String)
    /// 프로세스를 시작하지 못했다.
    case launchFailed
    /// 시간 제한이 지났다 (녹화는 제한을 두지 않아 오지 않는다).
    case timedOut
  }

  /// - Parameter fileSize: 끝난 뒤 파일 크기. 파일이 없으면 nil.
  static func decide(
    _ ending: Ending,
    sawStart: Bool,
    fileSize: Int?
  ) throws(SimulatorError) -> ScreenRecordingResult {
    let hasContent = (fileSize ?? 0) > 0
    switch ending {
    case .stopped:
      if hasContent {
        // 신호를 놓친 드문 경우도 화면이 담겼으면 저장으로 본다.
        return .saved
      }
      // 신호 뒤 비었으면 마무리가 늦어 SIGTERM·SIGKILL 로 끝난 것: 서비스가 기기를 끌 때 마무리한다 (측정).
      guard !sawStart else { throw .recordingUnfinished }
      return .stoppedBeforeStart
    case let .exited(code, stderr):
      if code == 0 {
        guard hasContent else { throw .recordingEmpty }
        return .saved
      }
      guard !hasContent else { return .savedAfterFailure }
      throw SimctlErrorClassifier.recordingError(exitCode: code, stderr: stderr)
    case .launchFailed:
      throw .developerToolsUnavailable
    case .timedOut:
      throw .commandFailed
    }
  }
}
