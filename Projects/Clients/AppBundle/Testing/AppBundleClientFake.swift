import AppBundleInterface
import Core
import Foundation
import Synchronization

/// 테스트·Example 용 `AppBundleClient`. 호출을 기록하고, 결과·에러·지연·멈춤을 바꿀 수 있다.
/// `inspect(_:)` 는 받은 URL 과 상관없이 설정한 정보(`setInfo(_:)`)를 돌려주고 파일은 읽지 않는다.
/// `extractApp(fromZip:)` 은 k 번째 호출(1부터)에 `.fake(index: k)` 를 돌려주고 파일을 만들지 않는다.
public final class AppBundleClientFake: AppBundleClient {
  public enum Call: Hashable, Sendable {
    case inspect(URL)
    case extractApp(URL)
    case removeExtracted(ExtractedApp)
  }

  private enum SuspendableCall: Hashable {
    case inspect, extract
  }

  private struct State {
    var info: AppBundleInfo
    var hostArchitecture: CPUArchitecture
    var calls: [Call] = []
    var inspectError: AppBundleError?
    var extractError: AppBundleError?
    var delay: Duration?
    var extractCount = 0
    var leftoverCleanupCount = 0
    var suspended: Set<SuspendableCall> = []
    var waiters: [SuspendableCall: [CheckedContinuation<Void, Never>]] = [:]
  }

  private let state: Mutex<State>

  public init(info: AppBundleInfo = .sample, hostArchitecture: CPUArchitecture = .arm64) {
    self.state = Mutex(State(info: info, hostArchitecture: hostArchitecture))
  }

  /// 들어온 호출 순서대로. 멈춘 호출도 들어오는 즉시 기록된다. `removeLeftoverExtractions()` 는 넣지 않는다
  /// (`leftoverCleanupCount` 로 센다).
  public var calls: [Call] {
    self.state.withLock { $0.calls }
  }

  /// `removeLeftoverExtractions()` 가 불린 횟수.
  public var leftoverCleanupCount: Int {
    self.state.withLock { $0.leftoverCleanupCount }
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

  /// non-nil 이면 `extractApp(fromZip:)` 이 풀기 결과 대신 이 에러를 던진다.
  public func setExtractError(_ error: AppBundleError?) {
    self.state.withLock { $0.extractError = error }
  }

  public func setHostArchitecture(_ architecture: CPUArchitecture) {
    self.state.withLock { $0.hostArchitecture = architecture }
  }

  /// Example 용. 검사·풀기가 결과를 내기 전에 이만큼 기다린다 (`nil` 이면 바로).
  public func setDelay(_ delay: Duration?) {
    self.state.withLock { $0.delay = delay }
  }

  /// 이후 `inspect(_:)` 가 기록만 하고 `resumeInspections()` 까지 기다린다.
  public func suspendInspections() {
    self.suspend(.inspect)
  }

  /// 기다리는 `inspect(_:)` 를 모두 깨우고, 이후 호출은 기다리지 않는다.
  public func resumeInspections() {
    self.resume(.inspect)
  }

  /// 이후 `extractApp(fromZip:)` 이 기록만 하고 `resumeExtractions()` 까지 기다린다. 검사의 멈춤과 따로다.
  public func suspendExtractions() {
    self.suspend(.extract)
  }

  /// 기다리는 `extractApp(fromZip:)` 을 모두 깨우고, 이후 호출은 기다리지 않는다.
  public func resumeExtractions() {
    self.resume(.extract)
  }

  /// 기록 → 멈춤 → 지연 → 설정된 에러면 던짐 → 정보. 깨어난 뒤의 설정을 쓴다.
  public func inspect(_ url: URL) async throws(AppBundleError) -> AppBundleInfo {
    self.state.withLock { $0.calls.append(.inspect(url)) }
    await self.waitIfSuspended(.inspect)
    await self.sleepIfNeeded()
    let result: Result<AppBundleInfo, AppBundleError> = self.state.withLock { state in
      if let error = state.inspectError {
        return .failure(error)
      }
      return .success(state.info)
    }
    return try result.get()
  }

  /// 기록 → 멈춤 → 지연 → 설정된 에러면 던짐 → `.fake(index: k)`. k 는 기록할 때 같은 lock 안에서 정하므로,
  /// 멈춘 호출을 어떤 순서로 깨워도 먼저 들어온 호출이 `.fake(index: 1)` 이다.
  public func extractApp(fromZip url: URL) async throws(AppBundleError) -> ExtractedApp {
    let index = self.state.withLock { state in
      state.calls.append(.extractApp(url))
      state.extractCount += 1
      return state.extractCount
    }
    await self.waitIfSuspended(.extract)
    await self.sleepIfNeeded()
    if let error = self.state.withLock({ $0.extractError }) {
      throw error
    }
    return .fake(index: index)
  }

  /// 기록만 한다.
  public func removeExtracted(_ extracted: ExtractedApp) async {
    self.state.withLock { $0.calls.append(.removeExtracted(extracted)) }
  }

  /// `leftoverCleanupCount` 만 늘린다.
  public func removeLeftoverExtractions() async {
    self.state.withLock { $0.leftoverCleanupCount += 1 }
  }

  private func sleepIfNeeded() async {
    if let delay = self.state.withLock({ $0.delay }) {
      try? await Task.sleep(for: delay)
    }
  }

  private func suspend(_ call: SuspendableCall) {
    _ = self.state.withLock { $0.suspended.insert(call) }
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
