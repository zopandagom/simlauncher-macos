import Core
import SimulatorInterface
import Synchronization

/// 테스트·Example 용 `SimulatorClient`. 호출을 기록하고, 결과·에러·지연·멈춤을 바꿀 수 있다.
/// boot 가 성공하면 그 기기를 `.booted`, shutdown 이 성공하면 `.shutdown` 으로 바꾼 목록을 저장한다.
public final class SimulatorClientFake: SimulatorClient {
  public enum Call: Hashable, Sendable {
    case fetchInventory
    case boot(VirtualDevice.ID)
    case shutdown(VirtualDevice.ID)
    case openSimulatorApp
  }

  private struct State {
    var inventory: DeviceInventory
    var calls: [Call] = []
    var fetchError: SimulatorError?
    var bootError: SimulatorError?
    var shutdownError: SimulatorError?
    var openAppError: SimulatorError?
    var delay: Duration?
    var fetchesSuspended = false
    var fetchWaiters: [CheckedContinuation<Void, Never>] = []
    var bootsSuspended = false
    var bootWaiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state: Mutex<State>

  public init(inventory: DeviceInventory = DeviceInventory(devices: [], runtimes: [])) {
    self.state = Mutex(State(inventory: inventory))
  }

  /// 들어온 호출 순서대로. 멈춘 호출도 들어오는 즉시 기록된다.
  public var calls: [Call] {
    self.state.withLock { $0.calls }
  }

  public func setInventory(_ inventory: DeviceInventory) {
    self.state.withLock { $0.inventory = inventory }
  }

  public func setFetchError(_ error: SimulatorError?) {
    self.state.withLock { $0.fetchError = error }
  }

  public func setBootError(_ error: SimulatorError?) {
    self.state.withLock { $0.bootError = error }
  }

  public func setShutdownError(_ error: SimulatorError?) {
    self.state.withLock { $0.shutdownError = error }
  }

  public func setOpenAppError(_ error: SimulatorError?) {
    self.state.withLock { $0.openAppError = error }
  }

  /// Example 용. 모든 호출이 결과를 내기 전에 이만큼 기다린다 (`nil` 이면 바로).
  public func setDelay(_ delay: Duration?) {
    self.state.withLock { $0.delay = delay }
  }

  /// 이후 `fetchInventory()` 가 기록만 하고 `resumeFetches()` 까지 기다린다.
  public func suspendFetches() {
    self.state.withLock { $0.fetchesSuspended = true }
  }

  /// 기다리는 `fetchInventory()` 를 모두 깨우고, 이후 호출은 기다리지 않는다.
  public func resumeFetches() {
    let waiters = self.state.withLock { state in
      state.fetchesSuspended = false
      let waiters = state.fetchWaiters
      state.fetchWaiters = []
      return waiters
    }
    for waiter in waiters {
      waiter.resume()
    }
  }

  /// 이후 `boot(_:)` 가 기록만 하고 `resumeBoots()` 까지 기다린다.
  public func suspendBoots() {
    self.state.withLock { $0.bootsSuspended = true }
  }

  /// 기다리는 `boot(_:)` 를 모두 깨우고, 이후 호출은 기다리지 않는다.
  public func resumeBoots() {
    let waiters = self.state.withLock { state in
      state.bootsSuspended = false
      let waiters = state.bootWaiters
      state.bootWaiters = []
      return waiters
    }
    for waiter in waiters {
      waiter.resume()
    }
  }

  public func fetchInventory() async throws(SimulatorError) -> DeviceInventory {
    self.record(.fetchInventory)
    // 플래그 확인과 continuation 저장을 한 lock 안에서 해야 resume 이 저장보다 먼저 와도 놓치지 않는다.
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let wait = self.state.withLock { state in
        guard state.fetchesSuspended else { return false }
        state.fetchWaiters.append(continuation)
        return true
      }
      if !wait {
        continuation.resume()
      }
    }
    await self.sleepIfNeeded()
    let result: Result<DeviceInventory, SimulatorError> = self.state.withLock { state in
      if let error = state.fetchError {
        return .failure(error)
      }
      return .success(state.inventory)
    }
    return try result.get()
  }

  public func boot(_ id: VirtualDevice.ID) async throws(SimulatorError) {
    self.record(.boot(id))
    // 플래그 확인과 continuation 저장을 한 lock 안에서 해야 resume 이 저장보다 먼저 와도 놓치지 않는다.
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let wait = self.state.withLock { state in
        guard state.bootsSuspended else { return false }
        state.bootWaiters.append(continuation)
        return true
      }
      if !wait {
        continuation.resume()
      }
    }
    await self.sleepIfNeeded()
    let result: Result<Void, SimulatorError> = self.state.withLock { state in
      if let error = state.bootError {
        return .failure(error)
      }
      state.inventory = Self.inventory(state.inventory, setting: id, to: .booted)
      return .success(())
    }
    try result.get()
  }

  public func shutdown(_ id: VirtualDevice.ID) async throws(SimulatorError) {
    self.record(.shutdown(id))
    await self.sleepIfNeeded()
    let result: Result<Void, SimulatorError> = self.state.withLock { state in
      if let error = state.shutdownError {
        return .failure(error)
      }
      state.inventory = Self.inventory(state.inventory, setting: id, to: .shutdown)
      return .success(())
    }
    try result.get()
  }

  public func openSimulatorApp() async throws(SimulatorError) {
    self.record(.openSimulatorApp)
    await self.sleepIfNeeded()
    if let error = self.state.withLock({ $0.openAppError }) {
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

  private static func inventory(
    _ inventory: DeviceInventory,
    setting id: VirtualDevice.ID,
    to newState: VirtualDevice.State
  ) -> DeviceInventory {
    let devices = inventory.devices.map { device in
      guard device.id == id else { return device }
      return VirtualDevice(
        id: device.id,
        name: device.name,
        family: device.family,
        state: newState,
        availability: device.availability,
        runtime: device.runtime
      )
    }
    return DeviceInventory(devices: devices, runtimes: inventory.runtimes)
  }
}
