import Core
import DevEnvironmentInterface
import Synchronization

/// 테스트·Example 용 `DevEnvironmentClient`. 호출을 기록하고, 상태·에러·지연·멈춤을 바꿀 수 있다. 명령은 실행하지 않는다.
/// `selectedXcode()` 는 설정한 상태의 Xcode(`status.xcode`)를 돌려준다 (Impl 처럼 같은 규칙 결과를 함께 쓴다).
/// 멈춘 호출은 기록된 뒤 재개될 때까지 기다리고, 결과(상태·에러)는 재개한 뒤의 설정으로 정한다.
public final class DevEnvironmentClientFake: DevEnvironmentClient {
  public enum Call: Hashable, Sendable {
    case selectedXcode
    case checkEnvironment
    case openXcode
    case openXcodeInAppStore
  }

  private enum SuspendableCall: Hashable {
    case check, open
  }

  private struct State {
    var status: DevEnvironmentStatus
    var calls: [Call] = []
    var checkError: DevEnvironmentError?
    var openXcodeError: DevEnvironmentError?
    var openAppStoreError: DevEnvironmentError?
    var delay: Duration?
    var suspended: Set<SuspendableCall> = []
    var waiters: [SuspendableCall: [CheckedContinuation<Void, Never>]] = [:]
  }

  private let state: Mutex<State>

  public init(status: DevEnvironmentStatus = .ready(.sample)) {
    self.state = Mutex(State(status: status))
  }

  /// 들어온 호출 순서대로.
  public var calls: [Call] {
    self.state.withLock { $0.calls }
  }

  /// 이후 `checkEnvironment()` 결과와 `selectedXcode()`·`openXcode()` 가 쓰는 Xcode.
  public func setStatus(_ status: DevEnvironmentStatus) {
    self.state.withLock { $0.status = status }
  }

  /// non-nil 이면 `checkEnvironment()` 가 상태 대신 이 에러를 던진다.
  public func setCheckError(_ error: DevEnvironmentError?) {
    self.state.withLock { $0.checkError = error }
  }

  /// non-nil 이면 `openXcode()` 가 이 에러를 던진다 (Xcode 없음보다 우선).
  public func setOpenXcodeError(_ error: DevEnvironmentError?) {
    self.state.withLock { $0.openXcodeError = error }
  }

  /// non-nil 이면 `openXcodeInAppStore()` 가 이 에러를 던진다.
  public func setOpenAppStoreError(_ error: DevEnvironmentError?) {
    self.state.withLock { $0.openAppStoreError = error }
  }

  /// Example 용. `checkEnvironment()`·`openXcode()`·`openXcodeInAppStore()` 가 결과를 내기 전에 이만큼 기다린다
  /// (`nil` 이면 바로).
  public func setDelay(_ delay: Duration?) {
    self.state.withLock { $0.delay = delay }
  }

  /// 이후 `checkEnvironment()` 가 기록만 하고 `resumeChecks()` 까지 기다린다.
  public func suspendChecks() {
    self.suspend(.check)
  }

  /// 멈춘 `checkEnvironment()` 를 모두 재개하고, 이후 호출은 기다리지 않는다.
  public func resumeChecks() {
    self.resume(.check)
  }

  /// 이후 `openXcode()`·`openXcodeInAppStore()` 가 기록만 하고 `resumeOpens()` 까지 기다린다.
  public func suspendOpens() {
    self.suspend(.open)
  }

  /// 멈춘 열기를 모두 재개하고, 이후 호출은 기다리지 않는다.
  public func resumeOpens() {
    self.resume(.open)
  }

  public func selectedXcode() async -> XcodeInstallation? {
    self.state.withLock { state in
      state.calls.append(.selectedXcode)
      return state.status.xcode
    }
  }

  public func checkEnvironment() async throws(DevEnvironmentError) -> DevEnvironmentStatus {
    self.record(.checkEnvironment)
    await self.waitIfSuspended(.check)
    await self.sleepIfNeeded()
    let result: Result<DevEnvironmentStatus, DevEnvironmentError> = self.state.withLock { state in
      if let error = state.checkError {
        return .failure(error)
      }
      return .success(state.status)
    }
    return try result.get()
  }

  /// 설정한 에러 → 상태에 Xcode 가 없으면 `.xcodeNotFound` → 성공.
  public func openXcode() async throws(DevEnvironmentError) {
    self.record(.openXcode)
    await self.waitIfSuspended(.open)
    await self.sleepIfNeeded()
    let error: DevEnvironmentError? = self.state.withLock { state in
      if let error = state.openXcodeError {
        return error
      }
      return state.status.xcode == nil ? .xcodeNotFound : nil
    }
    if let error {
      throw error
    }
  }

  public func openXcodeInAppStore() async throws(DevEnvironmentError) {
    self.record(.openXcodeInAppStore)
    await self.waitIfSuspended(.open)
    await self.sleepIfNeeded()
    if let error = self.state.withLock({ $0.openAppStoreError }) {
      throw error
    }
  }

  private func record(_ call: Call) {
    self.state.withLock { $0.calls.append(call) }
  }

  private func sleepIfNeeded() async {
    if let delay = self.state.withLock({ $0.delay }) {
      try? await Task.sleep(for: delay)
    }
  }

  private func suspend(_ call: SuspendableCall) {
    self.state.withLock { _ = $0.suspended.insert(call) }
  }

  private func resume(_ call: SuspendableCall) {
    let waiters = self.state.withLock { state in
      state.suspended.remove(call)
      return state.waiters.removeValue(forKey: call) ?? []
    }
    for waiter in waiters {
      waiter.resume()
    }
  }

  private func waitIfSuspended(_ call: SuspendableCall) async {
    // 플래그 확인과 continuation 저장을 한 lock 안에서 해야 resume 이 저장보다 먼저 와도 놓치지 않는다.
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let wait = self.state.withLock { state in
        guard state.suspended.contains(call) else { return false }
        state.waiters[call, default: []].append(continuation)
        return true
      }
      if !wait {
        continuation.resume()
      }
    }
  }
}
