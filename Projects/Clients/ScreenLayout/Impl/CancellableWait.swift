import ScreenLayoutInterface
import Synchronization

/// 다른 Task 의 결과를 기다리되, 호출한 Task 가 취소되거나 상한이 지나면 곧바로 돌아온다. 기다리던 Task 는 건드리지 않는다
/// (러너 준비·멈춤·정리는 풀의 Task 라 창을 닫아도 계속한다).
///
/// 구현: 한 번만 resume 하는 continuation(`ResumeOnce`)에 "기다리던 Task 의 결과를 넘기는 비구조 Task", "상한 Task",
/// 취소 처리기가 경쟁한다. 먼저 온 값 하나만 쓰인다.
enum CancellableWait {
  /// `task` 의 결과. 호출한 Task 가 취소되면 곧바로 `.failure(.cancelled)`.
  static func value<T: Sendable>(
    of task: Task<Result<T, ScreenLayoutError>, Never>
  ) async -> Result<T, ScreenLayoutError> {
    await self.race(cancelled: .failure(.cancelled), timeout: nil) { await task.value }
  }

  /// `task` 가 끝나면 true. 호출한 Task 가 취소되거나 `timeout` 이 지나면 곧바로 false.
  static func finished(_ task: Task<Void, Never>, timeout: Duration? = nil) async -> Bool {
    await self.race(cancelled: false, timeout: timeout) {
      await task.value
      return true
    }
  }

  private static func race<T: Sendable>(
    cancelled: T,
    timeout: Duration?,
    _ work: @escaping @Sendable () async -> T
  ) async -> T {
    let once = ResumeOnce<T>()
    // 일 Task 는 기다리던 Task 의 값을 읽을 뿐이라 그대로 끝나게 둔다. 붙이기 전에 끝나면 값을 들고 있다가 붙일 때 넘긴다.
    Task { await once.resume(work()) }
    let timer = timeout.map { timeout in
      Task {
        try? await Task.sleep(for: timeout)
        once.resume(cancelled)
      }
    }
    let result = await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
        once.attach(continuation)
      }
    } onCancel: {
      once.resume(cancelled)
    }
    timer?.cancel()
    return result
  }
}

/// 한 번만 resume 하는 continuation. 붙이기 전에 온 값은 들고 있다가 붙일 때 넘긴다.
private final class ResumeOnce<T: Sendable>: Sendable {
  private enum State {
    case idle
    case waiting(CheckedContinuation<T, Never>)
    case pending(T)
    case done
  }

  private let state = Mutex<State>(.idle)

  func attach(_ continuation: CheckedContinuation<T, Never>) {
    let pending: T? = self.state.withLock { state in
      switch state {
      case .idle:
        state = .waiting(continuation)
        return nil
      case let .pending(value):
        state = .done
        return value
      case .waiting, .done:
        return nil
      }
    }
    if let pending {
      continuation.resume(returning: pending)
    }
  }

  func resume(_ value: T) {
    let continuation: CheckedContinuation<T, Never>? = self.state.withLock { state in
      switch state {
      case .idle:
        state = .pending(value)
        return nil
      case let .waiting(continuation):
        state = .done
        return continuation
      case .pending, .done:
        return nil
      }
    }
    continuation?.resume(returning: value)
  }
}
