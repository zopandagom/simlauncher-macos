import AndroidPackageInterface
import Core
import Foundation
import Synchronization

/// 테스트·Example 용 `AndroidPackageClient`. 호출을 기록하고, 결과·지연·멈춤을 바꿀 수 있다.
/// `inspect(_:)` 는 받은 URL 과 상관없이 설정한 결과(`setResult(_:)`)를 돌려주고 파일은 읽지 않는다.
public final class AndroidPackageClientFake: AndroidPackageClient {
  private struct State {
    var result: Result<AndroidPackageInfo, AndroidPackageError>
    var calls: [URL] = []
    var delay: Duration?
    var suspended = false
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state: Mutex<State>

  public init(result: Result<AndroidPackageInfo, AndroidPackageError> = .success(.sample())) {
    self.state = Mutex(State(result: result))
  }

  /// `inspect(_:)` 가 받은 URL, 들어온 순서대로. 멈춘 호출도 들어오는 즉시 기록된다.
  public var calls: [URL] {
    self.state.withLock { $0.calls }
  }

  /// 이후 모든 URL 의 검사 결과.
  public func setResult(_ result: Result<AndroidPackageInfo, AndroidPackageError>) {
    self.state.withLock { $0.result = result }
  }

  /// Example 용. 검사가 결과를 내기 전에 이만큼 기다린다 (`nil` 이면 바로).
  public func setDelay(_ delay: Duration?) {
    self.state.withLock { $0.delay = delay }
  }

  /// 이후 `inspect(_:)` 가 기록만 하고 `resume()` 까지 기다린다.
  public func suspend() {
    self.state.withLock { $0.suspended = true }
  }

  /// 기다리는 `inspect(_:)` 를 모두 깨우고, 이후 호출은 기다리지 않는다.
  public func resume() {
    let waiters = self.state.withLock { state in
      state.suspended = false
      defer { state.waiters = [] }
      return state.waiters
    }
    for waiter in waiters {
      waiter.resume()
    }
  }

  /// 기록 → 멈춤 → 지연 → 결과. 깨어난 뒤의 설정을 쓴다.
  public func inspect(_ url: URL) async throws(AndroidPackageError) -> AndroidPackageInfo {
    self.state.withLock { $0.calls.append(url) }
    await self.waitIfSuspended()
    if let delay = self.state.withLock({ $0.delay }) {
      try? await Task.sleep(for: delay)
    }
    return try self.state.withLock { $0.result }.get()
  }

  private func waitIfSuspended() async {
    // 플래그 확인과 continuation 저장을 한 lock 안에서 해야 resume 이 저장보다 먼저 와도 놓치지 않는다.
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let wait = self.state.withLock { state in
        guard state.suspended else { return false }
        state.waiters.append(continuation)
        return true
      }
      if !wait {
        continuation.resume()
      }
    }
  }
}
