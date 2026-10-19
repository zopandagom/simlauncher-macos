import Core
import Foundation
import SimulatorInterface
import Synchronization

/// 테스트·Example 용 `SimulatorClient`. 호출을 기록하고, 결과·에러·지연·멈춤을 바꿀 수 있다.
/// boot 가 성공하면 그 기기를 `.booted`, shutdown 이 성공하면 `.shutdown` 으로 바꾼 목록을 저장한다.
/// create 가 성공하면 꺼진 새 기기를 목록 끝에 더하고, delete 가 성공하면 그 기기를 뺀다. 꺼짐 여부는 검사하지 않는다.
/// 목록을 다시 만들 때 런타임·기기 종류는 그대로 둔다.
public final class SimulatorClientFake: SimulatorClient {
  public enum Call: Hashable, Sendable {
    case fetchInventory
    case boot(VirtualDevice.ID)
    case shutdown(VirtualDevice.ID)
    case openSimulatorApp
    case create(name: String, deviceType: DeviceType.ID, runtime: DeviceRuntime.ID)
    case delete(VirtualDevice.ID)
    case erase(VirtualDevice.ID)
  }

  private enum SuspendableCall: Hashable {
    case fetch, boot, create, delete, erase
  }

  private struct State {
    var inventory: DeviceInventory
    var calls: [Call] = []
    var fetchError: SimulatorError?
    var bootError: SimulatorError?
    var shutdownError: SimulatorError?
    var openAppError: SimulatorError?
    var createError: SimulatorError?
    var deleteError: SimulatorError?
    var eraseError: SimulatorError?
    var delay: Duration?
    var createdCount = 0
    var suspended: Set<SuspendableCall> = []
    var waiters: [SuspendableCall: [CheckedContinuation<Void, Never>]] = [:]
  }

  private let state: Mutex<State>

  public init(inventory: DeviceInventory = DeviceInventory(devices: [], runtimes: [], deviceTypes: [])) {
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

  public func setCreateError(_ error: SimulatorError?) {
    self.state.withLock { $0.createError = error }
  }

  public func setDeleteError(_ error: SimulatorError?) {
    self.state.withLock { $0.deleteError = error }
  }

  public func setEraseError(_ error: SimulatorError?) {
    self.state.withLock { $0.eraseError = error }
  }

  /// Example 용. 모든 호출이 결과를 내기 전에 이만큼 기다린다 (`nil` 이면 바로).
  public func setDelay(_ delay: Duration?) {
    self.state.withLock { $0.delay = delay }
  }

  /// 이후 `fetchInventory()` 가 기록만 하고 `resumeFetches()` 까지 기다린다.
  public func suspendFetches() {
    self.suspend(.fetch)
  }

  /// 기다리는 `fetchInventory()` 를 모두 깨우고, 이후 호출은 기다리지 않는다.
  public func resumeFetches() {
    self.resume(.fetch)
  }

  /// 이후 `boot(_:)` 가 기록만 하고 `resumeBoots()` 까지 기다린다.
  public func suspendBoots() {
    self.suspend(.boot)
  }

  /// 기다리는 `boot(_:)` 를 모두 깨우고, 이후 호출은 기다리지 않는다.
  public func resumeBoots() {
    self.resume(.boot)
  }

  /// 이후 `create(name:deviceType:runtime:)` 가 기록만 하고 `resumeCreates()` 까지 기다린다.
  public func suspendCreates() {
    self.suspend(.create)
  }

  /// 기다리는 `create(name:deviceType:runtime:)` 를 모두 깨우고, 이후 호출은 기다리지 않는다.
  public func resumeCreates() {
    self.resume(.create)
  }

  /// 이후 `delete(_:)` 가 기록만 하고 `resumeDeletes()` 까지 기다린다.
  public func suspendDeletes() {
    self.suspend(.delete)
  }

  /// 기다리는 `delete(_:)` 를 모두 깨우고, 이후 호출은 기다리지 않는다.
  public func resumeDeletes() {
    self.resume(.delete)
  }

  /// 이후 `erase(_:)` 가 기록만 하고 `resumeErases()` 까지 기다린다.
  public func suspendErases() {
    self.suspend(.erase)
  }

  /// 기다리는 `erase(_:)` 를 모두 깨우고, 이후 호출은 기다리지 않는다.
  public func resumeErases() {
    self.resume(.erase)
  }

  public func fetchInventory() async throws(SimulatorError) -> DeviceInventory {
    self.record(.fetchInventory)
    await self.waitIfSuspended(.fetch)
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
    await self.waitIfSuspended(.boot)
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

  /// 저장된 목록에 런타임·기기 종류가 없으면 `.creationOptionUnavailable`.
  /// 새 UDID 는 `00000000-0000-0000-0001-` 뒤에 1 부터 늘어나는 12 자리 번호다.
  public func create(
    name: String,
    deviceType: DeviceType.ID,
    runtime: DeviceRuntime.ID
  ) async throws(SimulatorError) -> VirtualDevice.ID {
    self.record(.create(name: name, deviceType: deviceType, runtime: runtime))
    await self.waitIfSuspended(.create)
    await self.sleepIfNeeded()
    let result: Result<VirtualDevice.ID, SimulatorError> = self.state.withLock { state in
      if let error = state.createError {
        return .failure(error)
      }
      let inventory = state.inventory
      guard
        let foundRuntime = inventory.runtimes.first(where: { $0.id == runtime }),
        let foundType = inventory.deviceTypes.first(where: { $0.id == deviceType })
      else {
        return .failure(.creationOptionUnavailable)
      }
      state.createdCount += 1
      let id = VirtualDevice.ID("00000000-0000-0000-0001-\(String(format: "%012d", state.createdCount))")
      let device = VirtualDevice(
        id: id,
        name: name,
        family: foundType.family,
        state: .shutdown,
        availability: .available,
        runtime: foundRuntime
      )
      state.inventory = Self.inventory(inventory, devices: inventory.devices + [device])
      return .success(id)
    }
    return try result.get()
  }

  /// 목록에 없는 기기여도 성공한다.
  public func delete(_ id: VirtualDevice.ID) async throws(SimulatorError) {
    self.record(.delete(id))
    await self.waitIfSuspended(.delete)
    await self.sleepIfNeeded()
    let result: Result<Void, SimulatorError> = self.state.withLock { state in
      if let error = state.deleteError {
        return .failure(error)
      }
      state.inventory = Self.inventory(state.inventory, devices: state.inventory.devices.filter { $0.id != id })
      return .success(())
    }
    try result.get()
  }

  /// 성공해도 목록은 바뀌지 않는다.
  public func erase(_ id: VirtualDevice.ID) async throws(SimulatorError) {
    self.record(.erase(id))
    await self.waitIfSuspended(.erase)
    await self.sleepIfNeeded()
    if let error = self.state.withLock({ $0.eraseError }) {
      throw error
    }
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
    return Self.inventory(inventory, devices: devices)
  }

  /// 기기만 바꾸고 런타임·기기 종류는 그대로 둔 목록.
  private static func inventory(_ inventory: DeviceInventory, devices: [VirtualDevice]) -> DeviceInventory {
    DeviceInventory(devices: devices, runtimes: inventory.runtimes, deviceTypes: inventory.deviceTypes)
  }
}
