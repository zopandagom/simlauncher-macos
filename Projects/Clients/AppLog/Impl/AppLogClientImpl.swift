import AndroidEmulatorInterface
import AppLogInterface
import Core
import Foundation
import SimulatorInterface

/// 앱을 로그 받기와 함께 실행하고 세션별 버퍼에 출력을 쌓는 `AppLogClient`. iOS 는 `SimulatorClient.launchWithConsole`(simctl),
/// Android 는 `AndroidEmulatorClient.launchWithLogcat`(adb logcat).
/// 받기 작업은 세션마다 이 actor 가 만든 Task 이고 SimLauncher 가 켜져 있는 동안 이어진다 (`stopAll()` 로만 멈춘다).
/// 대체할 때 앞 세션의 받기는 **취소하지 않는다**: 앞 simctl 에 SIGINT 를 보내면 그 simctl 이 다루는 앱을 끄므로 새로 뜬 앱과 겹칠 위험이 있다.
/// 앞 simctl 은 새 실행·다시 설치가 앞 앱을 끝내면 스스로 끝나고(측정), 그때 대체 표시가 있으면 `.replaced` 다.
/// 판정은 "끝남이 오는 시점에 표시가 있느냐" 하나라 새 실행의 신호와 앞 simctl 의 끝 중 어느 쪽이 먼저여도 같다.
/// Android 도 같은 판정 하나를 쓰려고 앞 받기를 취소하지 않는다 (앞 adb 는 새 실행의 force-stop·다시 설치가 앱을 끝내면 143 으로 끝난다, 실측).
/// Android 의 끝남 원인은 받기 adb 의 끝으로 가른다 (목록을 다시 읽지 않는다).
public actor AppLogClientImpl: AppLogClient {
  struct LineSubscriber {
    let continuation: AsyncStream<AppLogLineUpdate>.Continuation
    /// 이 번호까지 보냈다.
    var deliveredThrough: Int
  }

  private let simulator: any SimulatorClient
  private let androidEmulator: any AndroidEmulatorClient
  let flushInterval: Duration
  private let launchSignalTimeout: Duration
  private nonisolated let running = RunningTasks()
  var table: AppLogSessionTable
  private var launchWaiters: [AppLogSessionID: CheckedContinuation<Result<Void, AppLogLaunchError>, Never>] = [:]
  private var timeoutTasks: [AppLogSessionID: Task<Void, Never>] = [:]
  var flushTasks: [AppLogSessionID: Task<Void, Never>] = [:]
  var lineSubscribers: [AppLogSessionID: [UUID: LineSubscriber]] = [:]
  var sessionSubscribers: [UUID: AsyncStream<[AppLogSessionSummary]>.Continuation] = [:]

  /// - Parameter androidEmulator: App 이 Android 기기 화면에 넣는 것과 같은 인스턴스 (Impl 은 하나만 만든다).
  public init(simulator: any SimulatorClient, androidEmulator: any AndroidEmulatorClient) {
    self.init(
      simulator: simulator,
      androidEmulator: androidEmulator,
      limits: .standard,
      flushInterval: .milliseconds(100),
      launchSignalTimeout: .seconds(60)
    )
  }

  /// 테스트용: 상한·묶음 간격(`.zero` 면 곧바로 보낸다)·실행 신호 대기 상한을 바꾼다.
  /// 신호 대기 상한은 앱이 아무것도 찍지 않고 simctl 의 신호 줄 형식이 바뀐 경우에도 실행 요청이 갇히지 않게 하는 값이다
  /// (막 켠 기기에서 실행이 수 초 걸리는 것보다 충분히 길게).
  init(
    simulator: any SimulatorClient,
    androidEmulator: any AndroidEmulatorClient,
    limits: AppLogLimits,
    flushInterval: Duration,
    launchSignalTimeout: Duration
  ) {
    self.simulator = simulator
    self.androidEmulator = androidEmulator
    self.table = AppLogSessionTable(limits: limits)
    self.flushInterval = flushInterval
    self.launchSignalTimeout = launchSignalTimeout
  }

  // MARK: - 실행

  public func launchIOSApp(
    _ bundleID: AppBundleID,
    appName: String,
    on device: VirtualDevice.ID,
    deviceName: String
  ) async throws(AppLogLaunchError) -> AppLogSessionID {
    try await self.start(AppLogLaunchSpec(app: .iOS(bundleID, device), appName: appName, deviceName: deviceName))
  }

  public func launchAndroidApp(
    _ package: AndroidPackageName,
    appName: String,
    on device: AndroidVirtualDevice.ID,
    deviceName: String
  ) async throws(AppLogLaunchError) -> AppLogSessionID {
    try await self.start(AppLogLaunchSpec(app: .android(package, device), appName: appName, deviceName: deviceName))
  }

  /// 기기를 켜지 않는다. 목록을 다시 읽어 그 기기가 켜져 있을 때만 Simulator 앱을 먼저 열어(실패는 무시) 실행 결과가 보이게 한다
  /// (설치 흐름의 켜기·앱 열기와 같은 결과를 켜기 없이). 꺼졌거나 없거나 목록을 읽지 못하면 앱을 열지 않는다: 켜진 기기가 없을 때
  /// Simulator 앱을 열면 앱이 기기를 켤 수 있다. 그때도 실행은 시도해 simctl 의 실패(`.deviceNotBooted` 등)를 그대로 던진다.
  /// Android 는 목록을 읽지 않고 바로 실행한다 (꺼져 있으면 실행의 사전 확인이 `.deviceNotBooted`).
  public func relaunch(_ session: AppLogSessionID) async throws(AppLogLaunchError) -> AppLogSessionID {
    guard !self.running.isStopping else {
      throw .commandFailed
    }
    guard let record = self.table.record(session), record.isPublished else {
      throw .sessionNotFound
    }
    if case let .iOS(_, device) = record.spec.app {
      let inventory = try? await self.simulator.fetchInventory()
      if inventory?.devices.first(where: { $0.id == device })?.state == .booted {
        try? await self.simulator.openSimulatorApp()
      }
    }
    return try await self.start(record.spec)
  }

  public func replacementWillStart(_ bundleID: AppBundleID, on device: VirtualDevice.ID) {
    self.table.markInstall(AppLogSessionKey(target: .iOS(device), appID: bundleID.rawValue))
  }

  public func replacementCancelled(_ bundleID: AppBundleID, on device: VirtualDevice.ID) {
    self.table.unmarkInstall(AppLogSessionKey(target: .iOS(device), appID: bundleID.rawValue))
  }

  public func replacementWillStart(_ package: AndroidPackageName, on device: AndroidVirtualDevice.ID) {
    self.table.markInstall(AppLogSessionKey(target: .android(device), appID: package.rawValue))
  }

  public func replacementCancelled(_ package: AndroidPackageName, on device: AndroidVirtualDevice.ID) {
    self.table.unmarkInstall(AppLogSessionKey(target: .android(device), appID: package.rawValue))
  }

  public nonisolated func stopAll() {
    self.running.stopAll()
  }

  /// 시작 중 세션을 넣고 받기 작업을 띄운 뒤, 실행 신호·실패·신호 대기 상한 중 먼저 온 것을 기다린다 (부른 Task 의 취소는 받지 않는다).
  private func start(_ spec: AppLogLaunchSpec) async throws(AppLogLaunchError) -> AppLogSessionID {
    guard !self.running.isStopping else {
      throw .commandFailed
    }
    let id = AppLogSessionID(UUID())
    let summary = AppLogSessionSummary(
      id: id,
      target: spec.target,
      deviceName: spec.deviceName,
      appID: spec.appID,
      appName: spec.appName,
      startedAt: Date(),
      state: .receiving
    )
    self.table.begin(summary, spec: spec)
    let result = await withCheckedContinuation { continuation in
      // 기다리는 쪽을 먼저 넣고 작업을 띄운다 (작업의 알림은 이 actor 를 거치므로 이 블록이 끝난 뒤에 온다).
      self.launchWaiters[id] = continuation
      self.startReceiving(id, spec: spec)
      self.startSignalTimer(id)
    }
    try result.get()
    return id
  }

  private func startReceiving(_ id: AppLogSessionID, spec: AppLogLaunchSpec) {
    let simulator = self.simulator
    let androidEmulator = self.androidEmulator
    let task = Task {
      let end: ReceiveEnd = switch spec.app {
      case let .iOS(bundleID, device):
        await Self.receiveIOS(bundleID, on: device, simulator: simulator) { event in
          await self.receive(event, for: id)
        }
      case let .android(package, device):
        await Self.receiveAndroid(package, on: device, emulator: androidEmulator) { event in
          await self.receive(event, for: id)
        }
      }
      await self.finished(id, end)
    }
    if !self.running.insert(id, task) {
      // `stopAll()` 이 그 사이 왔다: 띄우자마자 멈춘다 (시작 전이면 simctl·adb 를 실행하지 않는다).
      task.cancel()
    }
  }

  private func startSignalTimer(_ id: AppLogSessionID) {
    let timeout = self.launchSignalTimeout
    self.timeoutTasks[id] = Task {
      try? await Task.sleep(for: timeout)
      guard !Task.isCancelled else { return }
      await self.signalTimedOut(id)
    }
  }

  /// 신호도 끝남도 없이 상한이 지났다: simctl 은 그대로 두고 실행된 것으로 본다.
  private func signalTimedOut(_ id: AppLogSessionID) {
    self.timeoutTasks[id] = nil
    guard self.launchWaiters[id] != nil else { return }
    self.publish(id)
    self.resolveLaunch(id, .success(()))
  }

  private func resolveLaunch(_ id: AppLogSessionID, _ result: Result<Void, AppLogLaunchError>) {
    self.timeoutTasks.removeValue(forKey: id)?.cancel()
    self.launchWaiters.removeValue(forKey: id)?.resume(returning: result)
  }

  // MARK: - 받기

  private func receive(_ event: ReceiveEvent, for id: AppLogSessionID) {
    switch event {
    case .launched:
      guard self.launchWaiters[id] != nil else { return }
      self.publish(id)
      self.resolveLaunch(id, .success(()))
    case let .lines(texts):
      guard self.table.append(texts, to: id) else { return }
      self.scheduleFlush(id)
    }
  }

  /// simctl·adb 가 끝났다 (받기 작업의 끝). 공개 전 끝은 실패로 버리거나(던짐) 곧바로 끝난 세션으로 공개한다.
  private func finished(_ id: AppLogSessionID, _ end: ReceiveEnd) async {
    self.running.remove(id)
    guard let record = self.table.record(id) else { return }
    switch end {
    case .stopped:
      guard record.isPublished else {
        self.discard(id, failure: .commandFailed)
        return
      }
      self.endSession(id, reason: .stopped)
    case .exited:
      // 신호 없이 0 으로 끝나도 실행은 된 것으로 본다.
      self.publishIfNeeded(id, record)
      await self.judgeEnd(id)
    case .appExited:
      // Android 는 pid 전에 끝나도 `.launched` 를 먼저 보내므로 공개 전에는 오지 않지만 iOS 와 같게 둔다.
      self.publishIfNeeded(id, record)
      self.endReplacedOr(id, .appExited)
    case .connectionLost:
      guard record.isPublished else {
        self.discard(id, failure: .commandFailed)
        return
      }
      self.endReplacedOr(id, .deviceShutDown)
    case let .failed(error):
      await self.finishedFailed(id, record, error)
    }
  }

  private func finishedFailed(_ id: AppLogSessionID, _ record: AppLogSessionRecord, _ error: AppLogLaunchError) async {
    guard record.isPublished else {
      self.discard(id, failure: error)
      return
    }
    // 신호 대기 상한 뒤의 실패: 실패 알림은 이미 지나 끝남으로만 보인다.
    switch record.spec.app {
    case .iOS: await self.judgeEnd(id)
    case .android: self.endReplacedOr(id, .appExited)
    }
  }

  private func publishIfNeeded(_ id: AppLogSessionID, _ record: AppLogSessionRecord) {
    guard !record.isPublished else { return }
    self.publish(id)
    self.resolveLaunch(id, .success(()))
  }

  /// 대체 표시가 있으면 `.replaced`, 아니면 `reason` (Android: 목록을 읽지 않는다).
  private func endReplacedOr(_ id: AppLogSessionID, _ reason: AppLogEndReason) {
    self.endSession(id, reason: self.table.isReplacing(id) ? .replaced : reason)
  }

  /// 끝난 이유: 대체 표시가 있으면 `.replaced` (목록을 읽지 않는다). 아니면 목록을 다시 읽어 기기가 없거나 켜져 있지 않으면
  /// `.deviceShutDown` (끝난 직후 상태는 `Shutting Down`, 측정), 켜져 있거나 읽지 못하면 `.appExited`.
  private func judgeEnd(_ id: AppLogSessionID) async {
    guard let record = self.table.record(id) else { return }
    if self.table.isReplacing(id) {
      self.endSession(id, reason: .replaced)
      return
    }
    guard case let .iOS(_, deviceID) = record.spec.app else {
      self.endSession(id, reason: .appExited)
      return
    }
    let reason: AppLogEndReason
    do {
      let inventory = try await self.simulator.fetchInventory()
      let device = inventory.devices.first { $0.id == deviceID }
      reason = device?.state == .booted ? .appExited : .deviceShutDown
    } catch {
      reason = .appExited
    }
    self.endSession(id, reason: reason)
  }

  private func discard(_ id: AppLogSessionID, failure: AppLogLaunchError) {
    self.flushTasks.removeValue(forKey: id)?.cancel()
    self.table.discard(id)
    self.resolveLaunch(id, .failure(failure))
  }

  private func publish(_ id: AppLogSessionID) {
    guard let removed = self.table.publish(id) else { return }
    for removedID in removed {
      self.finishLineSubscribers(of: removedID)
    }
    self.broadcastSessions()
  }

  /// 남은 줄을 곧바로 보내고 끝냄으로 바꾼다.
  private func endSession(_ id: AppLogSessionID, reason: AppLogEndReason) {
    self.flushTasks.removeValue(forKey: id)?.cancel()
    self.flush(id)
    if self.table.end(id, reason: reason) {
      self.broadcastSessions()
    }
  }
}

// MARK: - 플랫폼별 받기

extension AppLogClientImpl {
  /// 받기 작업이 actor 에 넘기는 알림 (플랫폼 공용).
  enum ReceiveEvent: Sendable {
    case launched
    case lines([String])
  }

  /// 받기 작업의 끝 (플랫폼 공용).
  enum ReceiveEnd: Sendable {
    /// iOS: simctl 이 스스로 끝났다 (원인은 목록을 다시 읽어 가른다).
    case exited
    /// Android: 앱 메인 프로세스가 끝났다.
    case appExited
    /// Android: 앱이 끝나기 전에 adb 가 끝났다 (기기 꺼짐·연결 끊김).
    case connectionLost
    /// 받기 작업이 취소되어 멈췄다.
    case stopped
    /// 실행 실패 (공개 전이면 그대로 던진다).
    case failed(AppLogLaunchError)
  }

  static func receiveIOS(
    _ bundleID: AppBundleID,
    on device: VirtualDevice.ID,
    simulator: any SimulatorClient,
    onEvent: @escaping @Sendable (ReceiveEvent) async -> Void
  ) async -> ReceiveEnd {
    do throws(SimulatorError) {
      let end = try await simulator.launchWithConsole(bundleID, on: device) { event in
        switch event {
        case .launched: await onEvent(.launched)
        case let .lines(texts): await onEvent(.lines(texts))
        }
      }
      switch end {
      case .exited: return .exited
      case .stopped: return .stopped
      }
    } catch {
      return .failed(AppLogLaunchError(error))
    }
  }

  static func receiveAndroid(
    _ package: AndroidPackageName,
    on device: AndroidVirtualDevice.ID,
    emulator: any AndroidEmulatorClient,
    onEvent: @escaping @Sendable (ReceiveEvent) async -> Void
  ) async -> ReceiveEnd {
    do throws(AndroidEmulatorError) {
      let end = try await emulator.launchWithLogcat(package, on: device) { event in
        switch event {
        case .launched: await onEvent(.launched)
        case let .lines(texts): await onEvent(.lines(texts))
        }
      }
      switch end {
      case .appExited: return .appExited
      case .connectionLost: return .connectionLost
      case .stopped: return .stopped
      }
    } catch {
      return .failed(AppLogLaunchError(error))
    }
  }
}
