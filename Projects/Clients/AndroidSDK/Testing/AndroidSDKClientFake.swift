import AndroidSDKInterface
import Core
import Foundation
import Synchronization

/// 테스트·Example 용 `AndroidSDKClient`. 호출을 기록하고, 상태·계획·설치 결과·지연·멈춤을 바꿀 수 있다. 파일·네트워크·명령을
/// 쓰지 않는다.
/// - `checkSDK` 는 설정한 상태 (기본 `.absentSample`). 멈춤(`suspendChecks()`) 중이면 재개까지 기다린 뒤 그때의 상태.
/// - `fetchInstallPlan` 은 기록 → 취소 확인 → 멈춤 → 지연 → 취소 확인 → 결과 (기본 `.success(.sample)`). Impl 과 같은 취소 계약:
///   시작 전·멈춤 중·결과 전에 취소됐으면 `.cancelled`.
/// - `install` 은 기록 → Impl 과 같은 라이선스 판정(계획 원문의 지문이 모두 `acceptedLicenses` 에 없으면 알림 없이
///   `.licenseNotAccepted`) → 취소 확인 → 진행을 순서대로 알림(사이마다 지연·취소 확인) → 멈춤 → 지연 → 취소 확인 → 결과.
///   진행 기본값은 `[.firstSample]`, 결과 기본값은 계획의 패키지를 모두 설치함. 멈춘 설치에는 `sendInstallProgress(_:)` 로
///   진행을 더 보낼 수 있다. 마무리 단계의 "취소를 받지 않음" 은 흉내 내지 않는다 (멈춘 설치는 취소되면 `.cancelled`).
/// - `inspectCandidateFolder` 는 주소별 결과(`setCandidateResult(_:for:)`)가 있으면 그것, 없으면 공통 결과(기본 `.empty`, 쓸 수 있음).
///   멈춤(`suspendInspections()`) 중이면 재개까지 기다린다.
public final class AndroidSDKClientFake: AndroidSDKClient {
  public enum Call: Hashable, Sendable {
    case checkSDK
    case fetchInstallPlan
    case install(AndroidSDKInstallPlan, acceptedLicenses: Set<String>)
    case removeLeftovers
    case inspectCandidateFolder(URL)
  }

  public typealias CandidateResult = (candidate: AndroidSDKFolderCandidate, writable: Bool)

  private enum Gate: Hashable {
    case check, plan, install, inspect
  }

  private struct Waiter {
    let gate: Gate
    let continuation: CheckedContinuation<Bool, Never>
  }

  private struct State {
    var status: AndroidSDKStatus
    var calls: [Call] = []
    var planResult: Result<AndroidSDKInstallPlan, AndroidSDKPlanError> = .success(.sample)
    var installProgress: [AndroidSDKInstallProgress] = [.firstSample]
    /// nil 이면 계획의 패키지를 모두 설치함.
    var installResult: Result<AndroidSDKInstallOutcome, AndroidSDKInstallError>?
    var commonCandidate: CandidateResult = (.empty, true)
    var candidatesByPath: [String: CandidateResult] = [:]
    var delay: Duration?
    var suspended: Set<Gate> = []
    /// 멈춘 호출. 재개면 true, 취소면 false 로 깨우고 목록에서 뺀다.
    var waiters: [UUID: Waiter] = [:]
    /// 기다리기 전에 취소가 먼저 온 호출.
    var cancelledWaits: Set<UUID> = []
    /// 멈춘 설치의 progress 클로저. `sendInstallProgress(_:)` 가 부른다.
    var installProgressHandlers: [UUID: @Sendable (AndroidSDKInstallProgress) async -> Void] = [:]
  }

  private let state: Mutex<State>

  public init(status: AndroidSDKStatus = .absentSample) {
    self.state = Mutex(State(status: status))
  }

  /// 들어온 호출 순서대로. 멈춘 호출도 들어오는 즉시 기록된다.
  public var calls: [Call] {
    self.state.withLock { $0.calls }
  }

  /// 이후 `checkSDK()` 결과.
  public func setStatus(_ status: AndroidSDKStatus) {
    self.state.withLock { $0.status = status }
  }

  /// 이후 `fetchInstallPlan()` 결과.
  public func setPlanResult(_ result: Result<AndroidSDKInstallPlan, AndroidSDKPlanError>) {
    self.state.withLock { $0.planResult = result }
  }

  /// 이후 `install` 이 `progress` 를 순서대로 알린 뒤 `result` 로 끝난다. `result` 가 nil 이면 계획의 패키지를 모두 설치함.
  /// 결과는 끝날 때의 설정을 쓴다.
  public func setInstallScript(
    progress: [AndroidSDKInstallProgress],
    result: Result<AndroidSDKInstallOutcome, AndroidSDKInstallError>?
  ) {
    self.state.withLock { state in
      state.installProgress = progress
      state.installResult = result
    }
  }

  /// 이후 `inspectCandidateFolder` 의 공통 결과.
  public func setCandidateResult(_ result: CandidateResult) {
    self.state.withLock { $0.commonCandidate = result }
  }

  /// 이후 `url` 로 들어오는 `inspectCandidateFolder` 결과 (경로 `path(percentEncoded: false)` 로 비교). 공통 결과보다 먼저 쓴다.
  public func setCandidateResult(_ result: CandidateResult, for url: URL) {
    self.state.withLock { $0.candidatesByPath[Self.key(url)] = result }
  }

  /// Example 용. 각 메서드가 결과 전에 이만큼 기다린다 (`install` 은 진행 알림 사이에도). `nil` 이면 바로.
  public func setDelay(_ delay: Duration?) {
    self.state.withLock { $0.delay = delay }
  }

  /// 이후 `checkSDK()` 가 기록만 하고 `resumeChecks()` 까지 기다린다 (취소를 받지 않는다, Impl 과 같다).
  public func suspendChecks() {
    self.suspend(.check)
  }

  public func resumeChecks() {
    self.resume(.check)
  }

  /// 이후 `fetchInstallPlan()` 이 기록·취소 확인 뒤 `resumePlans()` 까지 기다린다. 기다리는 동안 취소되면 `.cancelled`.
  public func suspendPlans() {
    self.suspend(.plan)
  }

  public func resumePlans() {
    self.resume(.plan)
  }

  /// 이후 `install` 이 진행 알림을 모두 보낸 뒤 결과 전에 `resumeInstalls()` 까지 기다린다. 기다리는 동안 취소되면 `.cancelled`.
  public func suspendInstalls() {
    self.suspend(.install)
  }

  public func resumeInstalls() {
    self.resume(.install)
  }

  /// 이후 `inspectCandidateFolder` 가 기록만 하고 `resumeInspections()` 까지 기다린다 (취소를 받지 않는다).
  public func suspendInspections() {
    self.suspend(.inspect)
  }

  public func resumeInspections() {
    self.resume(.inspect)
  }

  /// 지금 멈춰 재개를 기다리는 `checkSDK()` 수.
  public var suspendedCheckCount: Int {
    self.count(.check)
  }

  /// 지금 멈춰 재개를 기다리는 `fetchInstallPlan()` 수.
  public var suspendedPlanCount: Int {
    self.count(.plan)
  }

  /// 지금 멈춰 재개를 기다리는 `install` 수. 테스트가 `sendInstallProgress(_:)` 를 보내기 전에 기다린다.
  public var suspendedInstallCount: Int {
    self.count(.install)
  }

  /// 지금 멈춰 재개를 기다리는 `inspectCandidateFolder` 수.
  public var suspendedInspectionCount: Int {
    self.count(.inspect)
  }

  /// 멈춘 설치마다 그 설치의 `progress` 클로저로 `update` 를 알리고, 알림이 끝난 뒤 돌아온다. 멈춘 설치가 없으면 아무 일도 하지 않는다.
  public func sendInstallProgress(_ update: AndroidSDKInstallProgress) async {
    let handlers = self.state.withLock { Array($0.installProgressHandlers.values) }
    for handler in handlers {
      await handler(update)
    }
  }

  public func checkSDK() async -> AndroidSDKStatus {
    self.record(.checkSDK)
    _ = await self.waitIfSuspended(.check, cancellable: false)
    await self.sleepIfNeeded()
    return self.state.withLock { $0.status }
  }

  public func fetchInstallPlan() async throws(AndroidSDKPlanError) -> AndroidSDKInstallPlan {
    self.record(.fetchInstallPlan)
    guard !Task.isCancelled else {
      throw .cancelled
    }
    guard await self.waitIfSuspended(.plan, cancellable: true) else {
      throw .cancelled
    }
    await self.sleepIfNeeded()
    guard !Task.isCancelled else {
      throw .cancelled
    }
    return try self.state.withLock { $0.planResult }.get()
  }

  public func install(
    _ plan: AndroidSDKInstallPlan,
    acceptedLicenses: Set<String>,
    progress: @escaping @Sendable (AndroidSDKInstallProgress) async -> Void
  ) async throws(AndroidSDKInstallError) -> AndroidSDKInstallOutcome {
    let script = self.state.withLock { state in
      state.calls.append(.install(plan, acceptedLicenses: acceptedLicenses))
      return state.installProgress
    }
    guard plan.licensesToConfirm(accepted: acceptedLicenses).isEmpty else {
      throw .licenseNotAccepted
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
    guard await self.waitIfSuspended(.install, cancellable: true, progress: progress) else {
      throw .cancelled
    }
    await self.sleepIfNeeded()
    guard !Task.isCancelled else {
      throw .cancelled
    }
    let result = self.state.withLock { $0.installResult }
      ?? .success(AndroidSDKInstallOutcome(installed: plan.packages.map(\.component), alreadyPresent: []))
    return try result.get()
  }

  public func removeLeftovers() async {
    self.record(.removeLeftovers)
  }

  public func inspectCandidateFolder(_ url: URL) async -> (candidate: AndroidSDKFolderCandidate, writable: Bool) {
    self.record(.inspectCandidateFolder(url))
    _ = await self.waitIfSuspended(.inspect, cancellable: false)
    await self.sleepIfNeeded()
    return self.state.withLock { $0.candidatesByPath[Self.key(url)] ?? $0.commonCandidate }
  }

  private static func key(_ url: URL) -> String {
    url.path(percentEncoded: false)
  }

  private func record(_ call: Call) {
    self.state.withLock { $0.calls.append(call) }
  }

  private func sleepIfNeeded() async {
    if let delay = self.state.withLock({ $0.delay }) {
      try? await Task.sleep(for: delay)
    }
  }

  private func count(_ gate: Gate) -> Int {
    self.state.withLock { state in state.waiters.values.count(where: { $0.gate == gate }) }
  }

  private func suspend(_ gate: Gate) {
    self.state.withLock { _ = $0.suspended.insert(gate) }
  }

  private func resume(_ gate: Gate) {
    let ready: [CheckedContinuation<Bool, Never>] = self.state.withLock { state in
      state.suspended.remove(gate)
      var ready: [CheckedContinuation<Bool, Never>] = []
      for (id, waiter) in state.waiters where waiter.gate == gate {
        state.waiters[id] = nil
        state.installProgressHandlers[id] = nil
        ready.append(waiter.continuation)
      }
      return ready
    }
    for continuation in ready {
      continuation.resume(returning: true)
    }
  }

  /// 멈춤이 아니면 바로 true. 멈춤이면 재개(true)를 기다린다. `cancellable` 이면 Task 취소에 false 로 깨어난다.
  private func waitIfSuspended(
    _ gate: Gate,
    cancellable: Bool,
    progress: (@Sendable (AndroidSDKInstallProgress) async -> Void)? = nil
  ) async -> Bool {
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        // 플래그·취소 확인과 continuation 저장을 한 lock 안에서 해야 재개·취소를 놓치지 않는다.
        let immediate: Bool? = self.state.withLock { state in
          if state.cancelledWaits.remove(id) != nil {
            return false
          }
          guard state.suspended.contains(gate) else {
            return true
          }
          state.waiters[id] = Waiter(gate: gate, continuation: continuation)
          if let progress {
            state.installProgressHandlers[id] = progress
          }
          return nil
        }
        if let immediate {
          continuation.resume(returning: immediate)
        }
      }
    } onCancel: {
      guard cancellable else {
        return
      }
      let ready: CheckedContinuation<Bool, Never>? = self.state.withLock { state in
        state.installProgressHandlers[id] = nil
        guard let waiter = state.waiters.removeValue(forKey: id) else {
          if state.suspended.contains(gate) {
            state.cancelledWaits.insert(id)
          }
          return nil
        }
        return waiter.continuation
      }
      ready?.resume(returning: false)
    }
  }
}
