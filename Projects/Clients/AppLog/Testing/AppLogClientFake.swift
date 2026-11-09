import AppLogInterface
import Core
import Foundation
import Synchronization

/// 테스트·Example 용 `AppLogClient`. 호출을 기록하고, 세션·줄을 테스트가 직접 넣는다.
/// `launchIOSApp`·`launchAndroidApp` 은 처리기가 성공하면(없으면 성공) 받는 중 요약(대상 `.iOS`·`.android`)을 만들어 목록에 더하고
/// 그 ID 를 돌려준다.
/// `relaunch` 는 `setRelaunchResult` 로 정한 결과를 쓰고, 없으면 원래 세션과 같은 기기·앱의 받는 중 요약을 더한다(없는 세션이면 `.sessionNotFound`).
public final class AppLogClientFake: AppLogClient {
  public enum Call: Hashable, Sendable {
    case launchIOSApp(AppBundleID, VirtualDevice.ID)
    case relaunch(AppLogSessionID)
    case replacementWillStart(AppBundleID, VirtualDevice.ID)
    case replacementCancelled(AppBundleID, VirtualDevice.ID)
    case launchAndroidApp(AndroidPackageName, AndroidVirtualDevice.ID)
    case androidReplacementWillStart(AndroidPackageName, AndroidVirtualDevice.ID)
    case androidReplacementCancelled(AndroidPackageName, AndroidVirtualDevice.ID)
  }

  /// `launchIOSApp` 처리기. 던지면 실행 실패이고 세션은 생기지 않는다.
  public typealias LaunchHandler = @Sendable (AppBundleID, VirtualDevice.ID) async throws(AppLogLaunchError) -> Void
  /// `launchAndroidApp` 처리기. 던지면 실행 실패이고 세션은 생기지 않는다.
  public typealias AndroidLaunchHandler = @Sendable (
    AndroidPackageName,
    AndroidVirtualDevice.ID
  ) async throws(AppLogLaunchError) -> Void

  private struct LineStore {
    var lines: [AppLogLine] = []
    var nextIndex = 0
    var droppedCount = 0
    var subscribers: [UUID: AsyncStream<AppLogLineUpdate>.Continuation] = [:]
  }

  private struct State {
    var sessions: [AppLogSessionSummary]
    var calls: [Call] = []
    var stopAllCount = 0
    var lineStores: [AppLogSessionID: LineStore] = [:]
    var sessionSubscribers: [UUID: AsyncStream<[AppLogSessionSummary]>.Continuation] = [:]
    var relaunchResult: Result<AppLogSessionSummary, AppLogLaunchError>?
    var relaunchesSuspended = false
    var relaunchWaiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state: Mutex<State>
  private let launchHandler: LaunchHandler?
  private let androidLaunchHandler: AndroidLaunchHandler?

  public init(
    sessions: [AppLogSessionSummary] = [],
    launchHandler: LaunchHandler? = nil,
    androidLaunchHandler: AndroidLaunchHandler? = nil
  ) {
    self.state = Mutex(State(sessions: sessions))
    self.launchHandler = launchHandler
    self.androidLaunchHandler = androidLaunchHandler
  }

  /// 들어온 호출 순서대로 (`stopAll` 은 `stopAllCount`).
  public var calls: [Call] {
    self.state.withLock { $0.calls }
  }

  public var stopAllCount: Int {
    self.state.withLock { $0.stopAllCount }
  }

  /// 지금 세션 목록.
  public var sessions: [AppLogSessionSummary] {
    self.state.withLock { $0.sessions }
  }

  /// 이 세션의 줄 구독 중 끝나지 않은 수.
  public func activeLineSubscriptions(of id: AppLogSessionID) -> Int {
    self.state.withLock { $0.lineStores[id]?.subscribers.count ?? 0 }
  }

  // MARK: - 조종

  /// 세션을 더하거나(목록 끝) 같은 ID 면 바꾸고 요약 알림을 보낸다.
  public func publish(_ summary: AppLogSessionSummary) {
    self.state.withLock { state in
      if let index = state.sessions.firstIndex(where: { $0.id == summary.id }) {
        state.sessions[index] = summary
      } else {
        state.sessions.append(summary)
      }
      Self.broadcastSessions(state)
    }
  }

  /// 세션을 지우고(정리 흉내) 그 줄 구독을 끝낸 뒤 요약 알림을 보낸다.
  public func remove(_ id: AppLogSessionID) {
    // finish 는 onTermination(같은 lock 을 잡는다)을 그 자리에서 부를 수 있어 lock 밖에서 한다.
    let finished = self.state.withLock { state in
      state.sessions.removeAll { $0.id == id }
      Self.broadcastSessions(state)
      return state.lineStores.removeValue(forKey: id).map { Array($0.subscribers.values) } ?? []
    }
    for subscriber in finished {
      subscriber.finish()
    }
  }

  /// 세션에 줄을 더하고(번호는 이어서) 구독자에게 묶음으로 보낸다.
  public func append(_ texts: [String], to id: AppLogSessionID) {
    self.state.withLock { state in
      var store = state.lineStores[id] ?? LineStore()
      let start = store.nextIndex
      let lines = texts.enumerated().map { AppLogLine(index: start + $0.offset, text: $0.element) }
      store.nextIndex += texts.count
      store.lines.append(contentsOf: lines)
      let update = AppLogLineUpdate(isSnapshot: false, lines: lines, droppedCount: store.droppedCount)
      for subscriber in store.subscribers.values {
        subscriber.yield(update)
      }
      state.lineStores[id] = store
    }
  }

  /// 버퍼가 차서 앞 `count` 줄을 버린 것으로 하고(번호 < count 인 줄을 지운다) 빈 묶음으로 알린다.
  public func setDropped(_ count: Int, for id: AppLogSessionID) {
    self.state.withLock { state in
      var store = state.lineStores[id] ?? LineStore()
      store.droppedCount = count
      store.nextIndex = max(store.nextIndex, count)
      store.lines.removeAll { $0.index < count }
      let update = AppLogLineUpdate(isSnapshot: false, lines: [], droppedCount: count)
      for subscriber in store.subscribers.values {
        subscriber.yield(update)
      }
      state.lineStores[id] = store
    }
  }

  /// 이후 `relaunch` 의 결과. 성공이면 그 요약을 목록에 넣고 그 ID 를 돌려준다. nil 이면 기본 동작.
  public func setRelaunchResult(_ result: Result<AppLogSessionSummary, AppLogLaunchError>?) {
    self.state.withLock { $0.relaunchResult = result }
  }

  /// 이후 `relaunch` 가 기록만 하고 `resumeRelaunches()` 까지 기다린다.
  public func suspendRelaunches() {
    self.state.withLock { $0.relaunchesSuspended = true }
  }

  /// 기다리는 `relaunch` 를 모두 깨우고, 이후 호출은 기다리지 않는다.
  public func resumeRelaunches() {
    let waiters = self.state.withLock { state in
      state.relaunchesSuspended = false
      let waiters = state.relaunchWaiters
      state.relaunchWaiters = []
      return waiters
    }
    for waiter in waiters {
      waiter.resume()
    }
  }

  // MARK: - AppLogClient

  public func launchIOSApp(
    _ bundleID: AppBundleID,
    appName: String,
    on device: VirtualDevice.ID,
    deviceName: String
  ) async throws(AppLogLaunchError) -> AppLogSessionID {
    self.state.withLock { $0.calls.append(.launchIOSApp(bundleID, device)) }
    try await self.launchHandler?(bundleID, device)
    let summary = AppLogSessionSummary(
      id: AppLogSessionID(UUID()),
      target: .iOS(device),
      deviceName: deviceName,
      appID: bundleID.rawValue,
      appName: appName,
      startedAt: Date(),
      state: .receiving
    )
    self.publish(summary)
    return summary.id
  }

  public func launchAndroidApp(
    _ package: AndroidPackageName,
    appName: String,
    on device: AndroidVirtualDevice.ID,
    deviceName: String
  ) async throws(AppLogLaunchError) -> AppLogSessionID {
    self.state.withLock { $0.calls.append(.launchAndroidApp(package, device)) }
    try await self.androidLaunchHandler?(package, device)
    let summary = AppLogSessionSummary(
      id: AppLogSessionID(UUID()),
      target: .android(device),
      deviceName: deviceName,
      appID: package.rawValue,
      appName: appName,
      startedAt: Date(),
      state: .receiving
    )
    self.publish(summary)
    return summary.id
  }

  public func relaunch(_ session: AppLogSessionID) async throws(AppLogLaunchError) -> AppLogSessionID {
    self.state.withLock { $0.calls.append(.relaunch(session)) }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let wait = self.state.withLock { state in
        guard state.relaunchesSuspended else { return false }
        state.relaunchWaiters.append(continuation)
        return true
      }
      if !wait {
        continuation.resume()
      }
    }
    let result: Result<AppLogSessionSummary, AppLogLaunchError> = self.state.withLock { state in
      if let result = state.relaunchResult {
        return result
      }
      guard let original = state.sessions.first(where: { $0.id == session }) else {
        return .failure(.sessionNotFound)
      }
      return .success(
        AppLogSessionSummary(
          id: AppLogSessionID(UUID()),
          target: original.target,
          deviceName: original.deviceName,
          appID: original.appID,
          appName: original.appName,
          startedAt: Date(),
          state: .receiving
        )
      )
    }
    let summary = try result.get()
    self.publish(summary)
    return summary.id
  }

  public func replacementWillStart(_ bundleID: AppBundleID, on device: VirtualDevice.ID) async {
    self.state.withLock { $0.calls.append(.replacementWillStart(bundleID, device)) }
  }

  public func replacementCancelled(_ bundleID: AppBundleID, on device: VirtualDevice.ID) async {
    self.state.withLock { $0.calls.append(.replacementCancelled(bundleID, device)) }
  }

  public func replacementWillStart(_ package: AndroidPackageName, on device: AndroidVirtualDevice.ID) async {
    self.state.withLock { $0.calls.append(.androidReplacementWillStart(package, device)) }
  }

  public func replacementCancelled(_ package: AndroidPackageName, on device: AndroidVirtualDevice.ID) async {
    self.state.withLock { $0.calls.append(.androidReplacementCancelled(package, device)) }
  }

  /// 첫 알림은 지금 목록, 그 뒤는 `publish`·`remove`·실행 성공마다.
  public func sessionUpdates() async -> AsyncStream<[AppLogSessionSummary]> {
    let (stream, continuation) = AsyncStream<[AppLogSessionSummary]>.makeStream()
    let token = UUID()
    self.state.withLock { state in
      state.sessionSubscribers[token] = continuation
      continuation.yield(state.sessions)
    }
    continuation.onTermination = { [weak self] _ in
      self?.state.withLock { _ = $0.sessionSubscribers.removeValue(forKey: token) }
    }
    return stream
  }

  /// 첫 알림은 지금 줄 스냅숏, 그 뒤는 `append`·`setDropped` 마다. 목록에 없는 세션이면 곧바로 끝난다.
  public func lineUpdates(of session: AppLogSessionID) async -> AsyncStream<AppLogLineUpdate> {
    let (stream, continuation) = AsyncStream<AppLogLineUpdate>.makeStream()
    let token = UUID()
    let exists = self.state.withLock { state in
      guard state.sessions.contains(where: { $0.id == session }) else {
        return false
      }
      var store = state.lineStores[session] ?? LineStore()
      store.subscribers[token] = continuation
      continuation.yield(AppLogLineUpdate(isSnapshot: true, lines: store.lines, droppedCount: store.droppedCount))
      state.lineStores[session] = store
      return true
    }
    guard exists else {
      continuation.finish()
      return stream
    }
    continuation.onTermination = { [weak self] _ in
      self?.state.withLock { _ = $0.lineStores[session]?.subscribers.removeValue(forKey: token) }
    }
    return stream
  }

  public func stopAll() {
    self.state.withLock { $0.stopAllCount += 1 }
  }

  private static func broadcastSessions(_ state: State) {
    for subscriber in state.sessionSubscribers.values {
      subscriber.yield(state.sessions)
    }
  }
}
