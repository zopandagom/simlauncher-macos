import AppBundleInterface
import Core
import Foundation
import Synchronization

/// 테스트·Example 용 `AppBundleClient`. 호출을 기록하고, 결과·에러·지연·멈춤을 바꿀 수 있다.
/// `inspect(_:)` 는 받은 URL 과 상관없이 설정한 정보(`setInfo(_:)`)를 돌려주고 파일은 읽지 않는다.
public final class AppBundleClientFake: AppBundleClient {
  public enum Call: Hashable, Sendable {
    case inspect(URL)
  }

  private struct State {
    var info: AppBundleInfo
    var hostArchitecture: CPUArchitecture
    var calls: [Call] = []
    var inspectError: AppBundleError?
    var delay: Duration?
    var isSuspended = false
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state: Mutex<State>

  public init(info: AppBundleInfo = .sample, hostArchitecture: CPUArchitecture = .arm64) {
    self.state = Mutex(State(info: info, hostArchitecture: hostArchitecture))
  }

  /// 들어온 호출 순서대로. 멈춘 호출도 들어오는 즉시 기록된다.
  public var calls: [Call] {
    self.state.withLock { $0.calls }
  }

  public var hostArchitecture: CPUArchitecture {
    self.state.withLock { $0.hostArchitecture }
  }

  /// 이후 모든 URL 의 검사 결과.
  public func setInfo(_ info: AppBundleInfo) {
    self.state.withLock { $0.info = info }
  }

  /// non-nil 이면 정보 대신 이 에러를 던진다.
  public func setInspectError(_ error: AppBundleError?) {
    self.state.withLock { $0.inspectError = error }
  }

  public func setHostArchitecture(_ architecture: CPUArchitecture) {
    self.state.withLock { $0.hostArchitecture = architecture }
  }

  /// Example 용. 검사가 결과를 내기 전에 이만큼 기다린다 (`nil` 이면 바로).
  public func setDelay(_ delay: Duration?) {
    self.state.withLock { $0.delay = delay }
  }

  /// 이후 `inspect(_:)` 가 기록만 하고 `resumeInspections()` 까지 기다린다.
  public func suspendInspections() {
    self.state.withLock { $0.isSuspended = true }
  }

  /// 기다리는 `inspect(_:)` 를 모두 깨우고, 이후 호출은 기다리지 않는다.
  public func resumeInspections() {
    let waiters = self.state.withLock { state in
      state.isSuspended = false
      defer { state.waiters = [] }
      return state.waiters
    }
    for waiter in waiters {
      waiter.resume()
    }
  }

  /// 기록 → 멈춤 → 지연 → 설정된 에러면 던짐 → 정보. 깨어난 뒤의 설정을 쓴다.
  public func inspect(_ url: URL) async throws(AppBundleError) -> AppBundleInfo {
    self.state.withLock { $0.calls.append(.inspect(url)) }
    await self.waitIfSuspended()
    if let delay = self.state.withLock({ $0.delay }) {
      try? await Task.sleep(for: delay)
    }
    let result: Result<AppBundleInfo, AppBundleError> = self.state.withLock { state in
      if let error = state.inspectError {
        return .failure(error)
      }
      return .success(state.info)
    }
    return try result.get()
  }

  private func waitIfSuspended() async {
    // 플래그 확인과 continuation 저장을 한 lock 안에서 해야 resume 이 저장보다 먼저 와도 놓치지 않는다.
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let wait = self.state.withLock { state in
        guard state.isSuspended else { return false }
        state.waiters.append(continuation)
        return true
      }
      if !wait {
        continuation.resume()
      }
    }
  }
}
