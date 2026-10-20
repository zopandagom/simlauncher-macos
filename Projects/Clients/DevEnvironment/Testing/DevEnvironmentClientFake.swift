import Core
import DevEnvironmentInterface
import Foundation
import Synchronization

/// 테스트·Example 용 `DevEnvironmentClient`. 호출을 기록하고, 상태·에러·지연·멈춤을 바꿀 수 있다. 명령은 실행하지 않는다.
/// `selectedXcode()` 는 설정한 상태의 Xcode(`status.xcode`)를 돌려준다 (Impl 처럼 같은 규칙 결과를 함께 쓴다).
/// 멈춘 호출은 기록된 뒤 재개될 때까지 기다리고, 결과(상태·에러)는 재개한 뒤의 설정으로 정한다.
/// 예외: 설치의 `.xcodeNotFound` 는 멈추기 전, 부를 때의 설정으로 정한다.
/// 기본 iOS 런타임은 `DefaultIOSRuntime.sample`, 설치는 진행 `[.preparing]` 뒤 `.installed` (실제처럼 첫 알림 하나).
public final class DevEnvironmentClientFake: DevEnvironmentClient {
  public enum Call: Hashable, Sendable {
    case selectedXcode
    case checkEnvironment
    case openXcode
    case openXcodeInAppStore
    case defaultIOSRuntime
    case installDefaultIOSRuntime
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
    var defaultRuntime: DefaultIOSRuntime? = .sample
    var installProgress: [RuntimeInstallProgress] = [.preparing]
    var installResult: Result<RuntimeInstallOutcome, RuntimeInstallError> = .success(.installed)
    var installsSuspended = false
    /// 멈춘 설치. 재개면 true, 취소면 false 로 깨운다.
    var installWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    /// 기다리기 전에 취소가 먼저 온 설치.
    var cancelledInstallWaits: Set<UUID> = []
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
  /// (취소된 Task 이고 Xcode 가 있으면 `checkEnvironment()` 는 상태 대신 `.checkFailed`, `checkEnvironment()` 주석 참고)
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
  /// (`nil` 이면 바로). `installDefaultIOSRuntime` 은 진행 알림 사이와 결과 전에 기다린다
  /// (결과가 `.xcodeNotFound` 면 기다리지 않고, 취소되면 그 시점에 끝난다).
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

  /// 이후 `defaultIOSRuntime()` 결과.
  public func setDefaultIOSRuntime(_ runtime: DefaultIOSRuntime?) {
    self.state.withLock { $0.defaultRuntime = runtime }
  }

  /// 이후 `installDefaultIOSRuntime` 이 `progress` 를 순서대로 알린 뒤 `result` 로 끝난다.
  /// 예외: 부를 때 `result` 가 `.xcodeNotFound` 면 알림 없이 바로 던진다. 이미 취소됐거나 알림 사이·결과 전에
  /// 취소되면 그 시점에 `.cancelled` 로 끝난다 (Impl 과 다를 수 있음, `installDefaultIOSRuntime` 주석 참고).
  public func setInstallScript(
    progress: [RuntimeInstallProgress],
    result: Result<RuntimeInstallOutcome, RuntimeInstallError>
  ) {
    self.state.withLock { state in
      state.installProgress = progress
      state.installResult = result
    }
  }

  /// 이후 `installDefaultIOSRuntime` 이 진행 알림을 모두 보낸 뒤 결과 전에 `resumeInstalls()` 까지 기다린다.
  /// 기다리는 동안 Task 가 취소되면 `.cancelled` 를 던진다. 결과가 `.xcodeNotFound` 면 기다리지 않고,
  /// 알림 전·사이에 취소되면 기다리기 전에 `.cancelled` 로 끝난다.
  public func suspendInstalls() {
    self.state.withLock { $0.installsSuspended = true }
  }

  /// 멈춘 설치를 모두 재개하고, 이후 호출은 기다리지 않는다.
  public func resumeInstalls() {
    let waiters = self.state.withLock { state in
      state.installsSuspended = false
      let waiters = Array(state.installWaiters.values)
      state.installWaiters = [:]
      return waiters
    }
    for waiter in waiters {
      waiter.resume(returning: true)
    }
  }

  public func selectedXcode() async -> XcodeInstallation? {
    self.state.withLock { state in
      state.calls.append(.selectedXcode)
      return state.status.xcode
    }
  }

  /// 설정한 에러 → Xcode 가 있는 상태에서 Task 가 취소됐으면 `.checkFailed` (Impl 의 확인 명령이 취소로 멈춘 것과 같다.
  /// Xcode 가 없으면 Impl 도 확인 명령을 실행하지 않고 상태를 돌려준다) → 상태.
  /// Impl 은 확인 명령이 스스로 끝난 뒤 온 취소면 상태를 돌려줄 수 있다.
  public func checkEnvironment() async throws(DevEnvironmentError) -> DevEnvironmentStatus {
    self.record(.checkEnvironment)
    await self.waitIfSuspended(.check)
    await self.sleepIfNeeded()
    let cancelled = Task.isCancelled
    let result: Result<DevEnvironmentStatus, DevEnvironmentError> = self.state.withLock { state in
      if let error = state.checkError {
        return .failure(error)
      }
      if cancelled, state.status.xcode != nil {
        return .failure(.checkFailed)
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

  public func defaultIOSRuntime() async -> DefaultIOSRuntime? {
    self.state.withLock { state in
      state.calls.append(.defaultIOSRuntime)
      return state.defaultRuntime
    }
  }

  /// 설정한 진행을 순서대로 알리고(각 알림이 끝난 뒤 다음), 멈춤이면 재개를 기다린 뒤 그때의 결과로 끝난다.
  /// Impl 과 같은 순서: 부를 때 설정된 결과가 `.xcodeNotFound` 면 알림 없이 바로 던지고, 이미 취소됐으면 알림 없이 `.cancelled`.
  /// 알림 사이·멈춤 중·결과 전에 취소되면 그때 `.cancelled`. 결과 전 취소는 `.cancelled` 로 정한다
  /// (Impl 은 xcodebuild 가 스스로 끝난 뒤 온 취소면 결과를 돌려줄 수 있다. 그 순서를 흉내 내려면 취소하지 않은 Task 를 쓴다).
  public func installDefaultIOSRuntime(
    progress: @escaping @Sendable (RuntimeInstallProgress) async -> Void
  ) async throws(RuntimeInstallError) -> RuntimeInstallOutcome {
    let (script, result) = self.state.withLock { state in
      state.calls.append(.installDefaultIOSRuntime)
      return (state.installProgress, state.installResult)
    }
    if case .failure(.xcodeNotFound) = result {
      throw .xcodeNotFound
    }
    guard !Task.isCancelled else {
      throw .cancelled
    }
    for (index, update) in script.enumerated() {
      if index > 0 {
        await self.sleepIfNeeded()
      }
      guard !Task.isCancelled else {
        throw .cancelled
      }
      await progress(update)
    }
    guard await self.waitIfInstallsSuspended() else {
      throw .cancelled
    }
    await self.sleepIfNeeded()
    guard !Task.isCancelled else {
      throw .cancelled
    }
    // `.xcodeNotFound` 는 실행 전 실패라 알림을 보낸 뒤에는 나오지 않는다: 그 사이 바뀌었으면 부를 때의 결과를 쓴다.
    let latest = self.state.withLock { $0.installResult }
    if case .failure(.xcodeNotFound) = latest {
      return try result.get()
    }
    return try latest.get()
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

  /// 멈춤이 아니면 바로 true. 멈춤이면 재개(true)나 Task 취소(false)까지 기다린다.
  private func waitIfInstallsSuspended() async -> Bool {
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        // 플래그·취소 확인과 continuation 저장을 한 lock 안에서 해야 재개·취소를 놓치지 않는다.
        let immediate: Bool? = self.state.withLock { state in
          if state.cancelledInstallWaits.remove(id) != nil {
            return false
          }
          guard state.installsSuspended else {
            return true
          }
          state.installWaiters[id] = continuation
          return nil
        }
        if let immediate {
          continuation.resume(returning: immediate)
        }
      }
    } onCancel: {
      let waiter = self.state.withLock { state in
        guard let waiter = state.installWaiters.removeValue(forKey: id) else {
          if state.installsSuspended {
            state.cancelledInstallWaits.insert(id)
          }
          return CheckedContinuation<Bool, Never>?.none
        }
        return waiter
      }
      waiter?.resume(returning: false)
    }
  }
}
