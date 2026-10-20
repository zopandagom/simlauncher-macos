import CommandInterface
import Foundation
import Synchronization

/// `runCancellable` 한 번의 실행 상태: 프로세스 단계, 멈춘 이유, 쌓은 출력, 출력 전달 스트림.
/// 신호는 lock 안에서 종료 처리(`terminationHandler`)가 오기 전에만 pid 로 보낸다. 종료 처리가 온 뒤에는 보내지 않지만,
/// Foundation 이 프로세스를 거둔 뒤 종료 처리가 오기 전의 짧은 틈(그 사이 pid 가 재사용될 수 있다)은 막지 못한다.
/// `Process` 객체는 동시성 경계 밖으로 넘기지 않고 pid 만 쓴다.
final class ProcessControl: Sendable {
  /// 멈춤 단계 간격과, 프로세스가 끝난 뒤 EOF 를 기다리는 시간.
  struct Timing: Sendable {
    /// SIGINT 뒤 SIGTERM 까지.
    let interruptGrace: Duration
    /// SIGTERM 뒤 SIGKILL 까지.
    let terminateGrace: Duration
    /// 프로세스가 끝난 뒤 EOF 를 기다리는 시간. 손자 프로세스가 파이프를 쥐고 있으면 EOF 가 오지 않는다.
    let eofGrace: Duration

    static let standard = Timing(interruptGrace: .seconds(10), terminateGrace: .seconds(5), eofGrace: .seconds(2))
  }

  private enum Phase {
    case notStarted
    case running(pid_t)
    case exited(Int32)
  }

  private struct State {
    var phase: Phase = .notStarted
    /// 처음 온 멈춤 이유 하나 (`.cancelled`·`.timedOut`). 끝난 뒤에 온 요청은 남기지 않는다.
    var stopReason: CommandError?
    var stdout = Data()
    var stderr = Data()
    var openStreams = 2
    var outputClosed = false
    var exitWaiters: [CheckedContinuation<Int32, Never>] = []
    var outputWaiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state = Mutex(State())
  private let timing: Timing
  private let stdoutHandle: FileHandle
  private let stderrHandle: FileHandle
  private let continuation: AsyncStream<CommandOutput>.Continuation

  init(
    timing: Timing,
    stdout: FileHandle,
    stderr: FileHandle,
    continuation: AsyncStream<CommandOutput>.Continuation
  ) {
    self.timing = timing
    self.stdoutHandle = stdout
    self.stderrHandle = stderr
    self.continuation = continuation
  }

  // MARK: - 읽기

  /// 두 파이프를 읽기 시작한다. 멈추기로 한 뒤에도 EOF(또는 종료 뒤 eofGrace)까지 계속 읽는다:
  /// 안 읽으면 파이프 버퍼(64KB)가 차서 자식이 쓰기에서 막히고, SIGINT 로 끝날 프로세스가 SIGKILL 까지 간다.
  /// 조각은 받는 즉시 결과용으로 쌓는다 (전달 루프가 취소로 먼저 끝나도 결과는 온전하다).
  func startReading() {
    self.stdoutHandle.readabilityHandler = { [self] handle in
      self.read(handle, as: CommandOutput.stdout)
    }
    self.stderrHandle.readabilityHandler = { [self] handle in
      self.read(handle, as: CommandOutput.stderr)
    }
  }

  private func read(_ handle: FileHandle, as wrap: (Data) -> CommandOutput) {
    let data = handle.availableData
    guard !data.isEmpty else {
      handle.readabilityHandler = nil
      self.streamEnded()
      return
    }
    let output = wrap(data)
    self.state.withLock { state in
      switch output {
      case let .stdout(data):
        state.stdout.append(data)
      case let .stderr(data):
        state.stderr.append(data)
      }
      if !state.outputClosed {
        self.continuation.yield(output)
      }
    }
  }

  /// 한 파이프가 EOF 에 닿았다. 둘 다 닿으면 출력을 닫는다.
  private func streamEnded() {
    let waiters = self.state.withLock { state in
      state.openStreams -= 1
      return state.openStreams == 0 ? self.closeOutput(&state) : []
    }
    for waiter in waiters {
      waiter.resume()
    }
  }

  /// 읽기를 그만두고 출력을 닫는다 (시작하지 않았거나, 종료 뒤 eofGrace 가 지났을 때).
  func stopReading() {
    self.stdoutHandle.readabilityHandler = nil
    self.stderrHandle.readabilityHandler = nil
    let waiters = self.state.withLock { self.closeOutput(&$0) }
    for waiter in waiters {
      waiter.resume()
    }
  }

  /// lock 안에서 부른다. 처음 한 번만 스트림을 끝내고 기다리는 쪽을 돌려준다 (resume 은 lock 밖에서).
  private func closeOutput(_ state: inout State) -> [CheckedContinuation<Void, Never>] {
    guard !state.outputClosed else {
      return []
    }
    state.outputClosed = true
    self.continuation.finish()
    let waiters = state.outputWaiters
    state.outputWaiters = []
    return waiters
  }

  // MARK: - 프로세스 단계

  /// 시작 직전 확인. 이미 멈추기로 했으면(시작 전 취소) false 이고 실행하지 않는다.
  func shouldLaunch() -> Bool {
    self.state.withLock { $0.stopReason == nil }
  }

  /// 시작했다. 그 사이 멈추기로 했으면 바로 SIGINT 를 보낸다. 이미 끝났으면(종료 처리가 먼저 옴) 그대로 둔다.
  func launched(pid: pid_t) {
    self.state.withLock { state in
      guard case .notStarted = state.phase else {
        return
      }
      state.phase = .running(pid)
      if state.stopReason != nil {
        self.beginStopping(pid)
      }
    }
  }

  /// 프로세스가 끝났다 (`terminationHandler`). 기다리는 쪽을 깨우고, eofGrace 뒤에도 EOF 가 없으면 읽기를 그만둔다.
  func exited(_ exitCode: Int32) {
    let waiters = self.state.withLock { state in
      state.phase = .exited(exitCode)
      let waiters = state.exitWaiters
      state.exitWaiters = []
      return waiters
    }
    for waiter in waiters {
      waiter.resume(returning: exitCode)
    }
    self.schedule(after: self.timing.eofGrace) { control in
      if !control.state.withLock({ $0.outputClosed }) {
        control.stopReading()
      }
    }
  }

  /// 취소·시간 초과. 처음 온 이유만 남긴다. 이미 끝났으면 무시한다 (결과를 돌려준다).
  func requestStop(_ reason: CommandError) {
    self.state.withLock { state in
      guard state.stopReason == nil else {
        return
      }
      switch state.phase {
      case .exited:
        return
      case .notStarted:
        state.stopReason = reason
      case let .running(pid):
        state.stopReason = reason
        self.beginStopping(pid)
      }
    }
  }

  /// `timeout` 이 지나면 `.timedOut` 으로 멈춘다.
  func startTimer(_ timeout: Duration) {
    self.schedule(after: timeout) { control in
      control.requestStop(.timedOut)
    }
  }

  /// lock 안에서 부른다: SIGINT → (interruptGrace) SIGTERM → (terminateGrace) SIGKILL.
  private func beginStopping(_ pid: pid_t) {
    kill(pid, SIGINT)
    self.schedule(after: self.timing.interruptGrace) { control in
      guard control.signalIfRunning(SIGTERM) else {
        return
      }
      control.schedule(after: control.timing.terminateGrace) { control in
        _ = control.signalIfRunning(SIGKILL)
      }
    }
  }

  /// 아직 끝나지 않았으면 신호를 보내고 true.
  private func signalIfRunning(_ signal: Int32) -> Bool {
    self.state.withLock { state in
      guard case let .running(pid) = state.phase else {
        return false
      }
      kill(pid, signal)
      return true
    }
  }

  /// `delay` 뒤에 `work` 를 이 객체로 부른다. 작업은 객체를 약하게 잡는다: `runCancellable` 이 돌아온 뒤(종료·출력 닫힘 뒤)의
  /// 타이머는 할 일이 없고, 객체와 읽기 fd 를 마감까지 붙잡지 않게 한다. 돌아오기 전에는 `runCancellable` 이 객체를 붙잡는다.
  /// 작업은 `self` 를 잡지 말고 넘겨받은 객체를 쓴다.
  private func schedule(after delay: Duration, _ work: @escaping @Sendable (ProcessControl) -> Void) {
    DispatchQueue.global().asyncAfter(deadline: .now() + Self.dispatchInterval(delay)) { [weak self] in
      guard let self else {
        return
      }
      work(self)
    }
  }

  /// `Duration` 을 나노초 간격으로. 음수는 0, 30년 이상은 `.never`.
  static func dispatchInterval(_ duration: Duration) -> DispatchTimeInterval {
    let components = duration.components
    guard components.seconds >= 0 else {
      return .nanoseconds(0)
    }
    guard components.seconds < 1_000_000_000 else {
      return .never
    }
    let nanoseconds: Int64 = components.seconds * 1_000_000_000 + components.attoseconds / 1_000_000_000
    return .nanoseconds(Int(nanoseconds))
  }

  // MARK: - 기다리기·결과

  /// 프로세스가 끝날 때까지 기다린다. checked continuation 이라 Task 취소와 무관하게 기다린다.
  func waitForExit() async -> Int32 {
    await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
      let exitCode: Int32? = self.state.withLock { state in
        if case let .exited(exitCode) = state.phase {
          return exitCode
        }
        state.exitWaiters.append(continuation)
        return nil
      }
      if let exitCode {
        continuation.resume(returning: exitCode)
      }
    }
  }

  /// 출력이 닫힐 때까지(두 EOF 또는 종료 뒤 eofGrace) 기다린다. Task 취소와 무관하다.
  func waitForOutputEnd() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let closed = self.state.withLock { state in
        guard !state.outputClosed else {
          return true
        }
        state.outputWaiters.append(continuation)
        return false
      }
      if closed {
        continuation.resume()
      }
    }
  }

  /// 끝난 뒤의 결과: 멈춘 이유가 있으면 그 에러, 아니면 쌓은 전체 출력.
  func outcome(exitCode: Int32) -> Result<CommandResult, CommandError> {
    self.state.withLock { state in
      if let reason = state.stopReason {
        return .failure(reason)
      }
      return .success(CommandResult(exitCode: exitCode, stdout: state.stdout, stderr: state.stderr))
    }
  }
}
