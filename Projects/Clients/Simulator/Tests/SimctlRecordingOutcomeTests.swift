import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// 녹화 결과 판정표: 끝난 방식 × 시작 신호 × 파일 크기.
struct SimctlRecordingOutcomeTests {
  private static let busy = "An error was encountered processing the command (domain=NSPOSIXErrorDomain, code=16):\n"
    + "Host recording is already in progress\n"

  struct Row: Sendable, CustomTestStringConvertible {
    let name: String
    let ending: SimctlRecordingOutcome.Ending
    let sawStart: Bool
    let fileSize: Int?
    let expected: Result<ScreenRecordingResult, SimulatorError>

    var testDescription: String {
      self.name
    }
  }

  @Test(
    "끝난 방식·시작 신호·파일 크기로 결과를 정한다",
    arguments: [
      Row(name: "멈춤·신호·내용 있음 → saved", ending: .stopped, sawStart: true, fileSize: 125_000, expected: .success(.saved)),
      Row(
        name: "멈춤·신호·0바이트 → recordingUnfinished",
        ending: .stopped,
        sawStart: true,
        fileSize: 0,
        expected: .failure(.recordingUnfinished)
      ),
      Row(
        name: "멈춤·신호·파일 없음 → recordingUnfinished",
        ending: .stopped,
        sawStart: true,
        fileSize: nil,
        expected: .failure(.recordingUnfinished)
      ),
      Row(name: "멈춤·신호 없음·내용 있음 → saved", ending: .stopped, sawStart: false, fileSize: 1, expected: .success(.saved)),
      Row(
        name: "멈춤·신호 없음·0바이트 → stoppedBeforeStart",
        ending: .stopped,
        sawStart: false,
        fileSize: 0,
        expected: .success(.stoppedBeforeStart)
      ),
      Row(
        name: "멈춤·신호 없음·파일 없음 → stoppedBeforeStart",
        ending: .stopped,
        sawStart: false,
        fileSize: nil,
        expected: .success(.stoppedBeforeStart)
      ),
      Row(
        name: "exit 0·내용 있음 → saved",
        ending: .exited(code: 0, stderr: ""),
        sawStart: true,
        fileSize: 10,
        expected: .success(.saved)
      ),
      Row(
        name: "exit 0·0바이트 → recordingEmpty",
        ending: .exited(code: 0, stderr: ""),
        sawStart: true,
        fileSize: 0,
        expected: .failure(.recordingEmpty)
      ),
      Row(
        name: "exit 0·신호 없음·파일 없음 → recordingEmpty",
        ending: .exited(code: 0, stderr: ""),
        sawStart: false,
        fileSize: nil,
        expected: .failure(.recordingEmpty)
      ),
      Row(
        name: "exit ≠ 0·내용 있음 → savedAfterFailure",
        ending: .exited(code: 1, stderr: "x"),
        sawStart: true,
        fileSize: 4096,
        expected: .success(.savedAfterFailure)
      ),
      Row(
        name: "exit ≠ 0·신호 없음·내용 있음 → savedAfterFailure",
        ending: .exited(code: 16, stderr: Self.busy),
        sawStart: false,
        fileSize: 1,
        expected: .success(.savedAfterFailure)
      ),
      Row(
        name: "exit 16·파일 없음 → 분류한 recordingInProgress",
        ending: .exited(code: 16, stderr: Self.busy),
        sawStart: false,
        fileSize: nil,
        expected: .failure(.recordingInProgress)
      ),
      Row(
        name: "exit ≠ 0·0바이트·단서 없음 → 분류한 commandFailed",
        ending: .exited(code: 1, stderr: ""),
        sawStart: true,
        fileSize: 0,
        expected: .failure(.commandFailed)
      ),
      Row(
        name: "시작 실패 → developerToolsUnavailable",
        ending: .launchFailed,
        sawStart: false,
        fileSize: 10,
        expected: .failure(.developerToolsUnavailable)
      ),
      Row(
        name: "시간 초과 → commandFailed",
        ending: .timedOut,
        sawStart: true,
        fileSize: 10,
        expected: .failure(.commandFailed)
      ),
    ]
  )
  func decide(row: Row) {
    let actual: Result<ScreenRecordingResult, SimulatorError>
    do throws(SimulatorError) {
      actual = try .success(SimctlRecordingOutcome.decide(row.ending, sawStart: row.sawStart, fileSize: row.fileSize))
    } catch {
      actual = .failure(error)
    }
    #expect(actual == row.expected)
  }
}
