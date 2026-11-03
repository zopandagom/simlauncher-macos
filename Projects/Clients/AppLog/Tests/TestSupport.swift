import AppLogInterface
import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Synchronization
import Testing
@testable import AppLogImpl

/// `SimulatorClientFake` 의 콘솔 처리기로, 실행(`launchWithConsole`)마다 테스트가 알림과 끝을 정한다.
/// 받기 Task 가 취소되면 그 실행은 `.stopped` 로 끝난다 (`stopAll` 흉내).
final class ConsoleDriver: Sendable {
  private let runs = Mutex<[ConsoleRun]>([])

  init(_ simulator: SimulatorClientFake) {
    simulator.setConsoleHandler { [self] bundleID, device, emit throws(SimulatorError) in
      let run = ConsoleRun(bundleID: bundleID, device: device, emitter: emit)
      self.runs.withLock { $0.append(run) }
      let result = await withTaskCancellationHandler {
        await run.wait()
      } onCancel: {
        run.cancelled()
      }
      return try result.get()
    }
  }

  var count: Int {
    self.runs.withLock { $0.count }
  }

  /// `index` 번째 실행이 들어올 때까지 기다린다.
  func run(_ index: Int) async throws -> ConsoleRun {
    try await waitUntil { self.count > index }
    return self.runs.withLock { $0[index] }
  }
}

/// `ConsoleDriver` 가 받은 실행 하나.
final class ConsoleRun: Sendable {
  private struct State {
    var waiter: CheckedContinuation<Result<AppConsoleEnd, SimulatorError>, Never>?
    var result: Result<AppConsoleEnd, SimulatorError>?
    var wasCancelled = false
  }

  let bundleID: AppBundleID
  let device: VirtualDevice.ID
  private let emitter: @Sendable (AppConsoleEvent) async -> Void
  private let state = Mutex(State())

  init(
    bundleID: AppBundleID,
    device: VirtualDevice.ID,
    emitter: @escaping @Sendable (AppConsoleEvent) async -> Void
  ) {
    self.bundleID = bundleID
    self.device = device
    self.emitter = emitter
  }

  /// 받기 Task 가 취소됐다.
  var wasCancelled: Bool {
    self.state.withLock { $0.wasCancelled }
  }

  func emit(_ event: AppConsoleEvent) async {
    await self.emitter(event)
  }

  /// 실행을 끝낸다. 두 번째부터는 무시한다.
  func finish(_ result: Result<AppConsoleEnd, SimulatorError>) {
    let waiter = self.state.withLock { state -> CheckedContinuation<Result<AppConsoleEnd, SimulatorError>, Never>? in
      guard state.result == nil else { return nil }
      state.result = result
      let waiter = state.waiter
      state.waiter = nil
      return waiter
    }
    waiter?.resume(returning: result)
  }

  func cancelled() {
    self.state.withLock { $0.wasCancelled = true }
    self.finish(.success(.stopped))
  }

  func wait() async -> Result<AppConsoleEnd, SimulatorError> {
    await withCheckedContinuation { continuation in
      let ready = self.state.withLock { state -> Result<AppConsoleEnd, SimulatorError>? in
        if let result = state.result {
          return result
        }
        state.waiter = continuation
        return nil
      }
      if let ready {
        continuation.resume(returning: ready)
      }
    }
  }
}

/// 스트림을 끝까지 모은다.
final class Collector<Element: Sendable>: Sendable {
  private struct State {
    var values: [Element] = []
    var isFinished = false
  }

  private let state = Mutex(State())
  private let task = Mutex<Task<Void, Never>?>(nil)

  init(_ stream: AsyncStream<Element>) {
    let task = Task {
      for await value in stream {
        self.state.withLock { $0.values.append(value) }
      }
      self.state.withLock { $0.isFinished = true }
    }
    self.task.withLock { $0 = task }
  }

  var values: [Element] {
    self.state.withLock { $0.values }
  }

  var last: Element? {
    self.values.last
  }

  var isFinished: Bool {
    self.state.withLock { $0.isFinished }
  }

  /// 모으기를 멈춘다 (스트림의 onTermination 이 불린다).
  func cancel() {
    self.task.withLock { $0?.cancel() }
  }
}

/// 조건이 참이 될 때까지 5ms 마다 본다. 5초가 지나면 실패.
func waitUntil(_ condition: @Sendable () -> Bool) async throws {
  let deadline = ContinuousClock.now + .seconds(5)
  while !condition() {
    guard ContinuousClock.now < deadline else {
      Issue.record("5초 안에 조건이 참이 되지 않았다")
      throw CancellationError()
    }
    try await Task.sleep(for: .milliseconds(5))
  }
}

/// 테스트 대상과 흉내.
struct AppLogFixture {
  static let app = AppBundleID("dev.simlauncher.logprobe")!
  static let otherApp = AppBundleID("com.example.other")!

  let simulator: SimulatorClientFake
  let console: ConsoleDriver
  let client: AppLogClientImpl

  init(
    inventory: DeviceInventory = .sample,
    limits: AppLogLimits = .standard,
    flushInterval: Duration = .zero,
    launchSignalTimeout: Duration = .seconds(60)
  ) {
    self.simulator = SimulatorClientFake(inventory: inventory)
    self.console = ConsoleDriver(self.simulator)
    self.client = AppLogClientImpl(
      simulator: self.simulator,
      limits: limits,
      flushInterval: flushInterval,
      launchSignalTimeout: launchSignalTimeout
    )
  }

  /// 켜진 iPhone 에서 실행을 요청하는 Task (기다리지 않는다).
  func launch(
    _ bundleID: AppBundleID = Self.app,
    on device: VirtualDevice.ID = SampleID.iPhoneOn
  ) -> Task<AppLogSessionID, any Error> {
    let client = self.client
    return Task {
      try await client.launchIOSApp(bundleID, appName: "LogProbe", on: device, deviceName: "iPhone 17 Pro")
    }
  }

  /// 실행을 요청하고 `index` 번째 실행에 신호를 보내 세션 ID 를 받는다.
  func launched(
    _ bundleID: AppBundleID = Self.app,
    on device: VirtualDevice.ID = SampleID.iPhoneOn,
    run index: Int
  ) async throws -> (AppLogSessionID, ConsoleRun) {
    let task = self.launch(bundleID, on: device)
    let run = try await self.console.run(index)
    await run.emit(.launched)
    return try await (task.value, run)
  }

  /// 지금 세션 목록 (sessionUpdates 의 첫 알림).
  func summaries() async -> [AppLogSessionSummary] {
    for await summaries in await self.client.sessionUpdates() {
      return summaries
    }
    return []
  }

  /// 세션 상태가 조건을 만족할 때까지 기다린다.
  func waitForState(
    of id: AppLogSessionID,
    _ condition: @escaping @Sendable (AppLogSessionState?) -> Bool
  ) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while true {
      let state = await self.summaries().first { $0.id == id }?.state
      if condition(state) {
        return
      }
      guard ContinuousClock.now < deadline else {
        Issue.record("5초 안에 세션 상태가 바뀌지 않았다: \(String(describing: state))")
        throw CancellationError()
      }
      try await Task.sleep(for: .milliseconds(5))
    }
  }

  func waitForEnd(of id: AppLogSessionID) async throws -> AppLogEndReason? {
    try await self.waitForState(of: id) { state in
      if case .ended = state {
        return true
      }
      return false
    }
    guard case let .ended(reason) = await self.summaries().first(where: { $0.id == id })?.state else {
      return nil
    }
    return reason
  }
}
