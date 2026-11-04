import AppLogInterface
import Synchronization

/// 세션별 받기 작업 표. `stopAll()` 이 actor 를 거치지 않고(앱 종료 때 메인에서 동기로) 모두 취소할 수 있게 lock 으로 둔다.
/// `Task.cancel()` 은 그 자리에서 `withTaskCancellationHandler` 의 onCancel(→ simctl 에 SIGINT)을 부르므로, 앱이 끝나기 전에 신호가 나간다.
final class RunningTasks: Sendable {
  private struct State {
    var tasks: [AppLogSessionID: Task<Void, Never>] = [:]
    var isStopping = false
  }

  private let state = Mutex(State())

  /// `stopAll()` 뒤로 true.
  var isStopping: Bool {
    self.state.withLock { $0.isStopping }
  }

  /// 표에 넣는다. 이미 멈추는 중이면 넣지 않고 false (부른 쪽이 취소한다).
  func insert(_ id: AppLogSessionID, _ task: Task<Void, Never>) -> Bool {
    self.state.withLock { state in
      guard !state.isStopping else { return false }
      state.tasks[id] = task
      return true
    }
  }

  func remove(_ id: AppLogSessionID) {
    self.state.withLock { _ = $0.tasks.removeValue(forKey: id) }
  }

  /// 멈춤으로 바꾸고 표를 비운 뒤 모두 취소한다 (기다리지 않는다).
  func stopAll() {
    let tasks = self.state.withLock { state in
      state.isStopping = true
      let tasks = Array(state.tasks.values)
      state.tasks = [:]
      return tasks
    }
    for task in tasks {
      task.cancel()
    }
  }
}
