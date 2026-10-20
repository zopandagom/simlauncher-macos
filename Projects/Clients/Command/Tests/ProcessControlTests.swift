import CommandInterface
import Foundation
import Testing
@testable import CommandImpl

/// 걸어 둔 타이머가 `ProcessControl` 을 붙잡지 않는다 (돌아온 뒤 객체와 읽기 fd 가 마감까지 남지 않는다).
/// 시간을 재지 않고, 타이머가 걸린 채로 마지막 강한 참조를 놓은 뒤 약한 참조가 nil 인지 본다.
/// Tests 에서는 `Process` 를 만들 수 없어(lint `process_only_in_command_impl`) 직접 만든 `ProcessControl` 을 쓴다.
struct ProcessControlTests {
  /// 타이머가 테스트 중에 울리지 않도록 긴 간격.
  private static let timing = ProcessControl.Timing(
    interruptGrace: .seconds(60),
    terminateGrace: .seconds(60),
    eofGrace: .seconds(60)
  )

  /// `setUp` 으로 타이머를 건 객체를 만들고, 강한 참조를 놓은 뒤 풀렸는지 돌려준다.
  private static func isReleased(after setUp: (ProcessControl) -> Void) -> Bool {
    weak var weakControl: ProcessControl?
    do {
      let (_, continuation) = AsyncStream<CommandOutput>.makeStream()
      let control = ProcessControl(
        timing: Self.timing,
        stdout: Pipe().fileHandleForReading,
        stderr: Pipe().fileHandleForReading,
        continuation: continuation
      )
      weakControl = control
      setUp(control)
    }
    return weakControl == nil
  }

  @Test("시간 제한 타이머가 걸려 있어도 객체를 붙잡지 않는다")
  func timeoutTimerDoesNotRetain() {
    #expect(Self.isReleased { $0.startTimer(.seconds(60)) })
  }

  @Test("종료 뒤 eofGrace 타이머가 걸려 있어도 객체를 붙잡지 않는다")
  func eofGraceTimerDoesNotRetain() {
    // 시작 전에 종료 처리가 오면 바로 exited 가 되고 eofGrace 타이머가 걸린다.
    #expect(Self.isReleased { $0.exited(0) })
  }

  @Test("멈춤 단계(SIGTERM) 타이머가 걸려 있어도 객체를 붙잡지 않는다")
  func stopTimerDoesNotRetain() {
    // 없는 pid: macOS pid 상한 99,999 보다 큰 양수라 SIGINT 는 ESRCH 로 실패하고 SIGTERM 타이머만 걸린다.
    // 0·음수 pid 는 프로세스 그룹에 신호를 보내므로 절대 쓰지 않는다.
    #expect(Self.isReleased { control in
      control.launched(pid: 999_999)
      control.requestStop(.cancelled)
    })
  }
}
