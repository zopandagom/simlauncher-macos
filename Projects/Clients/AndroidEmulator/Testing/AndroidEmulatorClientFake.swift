import AndroidEmulatorInterface
import Core
import Foundation
import Synchronization

/// 테스트·Example 용 `AndroidEmulatorClient`. 호출을 기록하고, 결과·에러·지연·멈춤을 바꿀 수 있다. 파일·명령을 쓰지 않는다.
/// - `boot` 가 성공하면 그 기기를 `.booted`, `shutdown` 이 성공하면 `.shutdown` 으로 바꾼 목록을 저장한다.
///   목록에 없는 기기여도 성공하고, 쓸 수 있는지·상태는 검사하지 않는다 (Model 가드를 테스트한다).
/// - `create` 는 Impl 과 같은 순서로 검사한다: 표시 이름(`DeviceName.problem` → `.invalidDeviceName`) → 선택지
///   (`creationOptions.contains` 가 아니면 `.creationOptionUnavailable`) → AVD 이름(`AndroidAVDName.make`, 지금 목록의 이름 기준,
///   nil 이면 `.nameUnavailable`). 성공하면 꺼진 새 기기(표시 이름은 `DeviceName.normalized`)를 목록 끝에 더한다.
/// - `delete` 는 성공하면 그 기기를 빼고 설정한 결과(기본 `.deleted`)를 돌려준다. 목록에 없는 기기여도 성공한다.
/// - `erase` 는 성공해도 목록을 바꾸지 않는다.
/// - 앱 작업(`deviceTraits`·`install`·`launch`·`openURL`·`installedPackages`·`screenshot`·`recordScreen`)은 설정한 결과만 돌려주고
///   목록·기기 상태를 보지 않는다. 기본은 `AndroidDeviceTraits.sample`·성공·빈 앱 목록. 기기별 설정(`…(_:for:)`)이 전체 설정보다 먼저다.
/// - `screenshot`·`recordScreen` 은 파일을 만들거나 쓰지 않는다. `recordScreen` 은 기본으로 바로 시작 신호를 보내고 호출한 Task 가
///   취소될 때까지 기다린 뒤 `.saved` 를 돌려준다 (iOS `SimulatorClientFake.recordVideo` 와 같다).
/// - 멈춤(`suspend…`) 중인 호출은 기록만 하고 재개까지 기다린다 (취소를 받지 않는다). 결과는 깨어난 뒤의 설정을 쓴다.
public final class AndroidEmulatorClientFake: AndroidEmulatorClient {
  public enum Call: Hashable, Sendable {
    case fetchDevices
    case boot(AndroidVirtualDevice.ID)
    case shutdown(AndroidVirtualDevice.ID)
    case create(displayName: String, image: AndroidSystemImageRef, profile: AndroidDeviceProfile.ID)
    case delete(AndroidVirtualDevice.ID)
    case erase(AndroidVirtualDevice.ID)
    case deviceTraits(AndroidVirtualDevice.ID)
    case install(URL, AndroidVirtualDevice.ID)
    case launch(AndroidPackageName, AndroidVirtualDevice.ID)
    case openURL(DeepLink, AndroidVirtualDevice.ID)
    case installedPackages(AndroidVirtualDevice.ID)
    case screenshot(AndroidVirtualDevice.ID, URL)
    case recordScreen(AndroidVirtualDevice.ID, URL)
  }

  private enum SuspendableCall: Hashable {
    case fetch, boot, shutdown, create, delete, erase, install, packageList, screenshot, recording
    case bootOf(AndroidVirtualDevice.ID)
    case installOf(AndroidVirtualDevice.ID)
  }

  private struct State {
    var inventory: AndroidDeviceInventory
    var calls: [Call] = []
    var fetchError: AndroidEmulatorError?
    var bootErrors: [AndroidVirtualDevice.ID: AndroidEmulatorError] = [:]
    var bootError: AndroidEmulatorError?
    var shutdownError: AndroidEmulatorError?
    var createError: AndroidEmulatorError?
    var deleteResult: Result<AndroidDeleteOutcome, AndroidEmulatorError> = .success(.deleted)
    var eraseError: AndroidEmulatorError?
    var deviceTraits: Result<AndroidDeviceTraits, AndroidEmulatorError> = .success(.sample)
    var deviceTraitsByDevice: [AndroidVirtualDevice.ID: Result<AndroidDeviceTraits, AndroidEmulatorError>] = [:]
    var installError: AndroidEmulatorError?
    var installErrors: [AndroidVirtualDevice.ID: AndroidEmulatorError] = [:]
    var launchError: AndroidEmulatorError?
    var launchErrors: [AndroidVirtualDevice.ID: AndroidEmulatorError] = [:]
    var screenshotError: AndroidEmulatorError?
    var recordingResult: Result<AndroidScreenRecordingResult, AndroidEmulatorError>?
    var recordingEndsByItself: Result<AndroidScreenRecordingResult, AndroidEmulatorError>?
    var recordingSignalsStart = true
    var openURLError: AndroidEmulatorError?
    var installedPackages: Result<[AndroidPackageName], AndroidEmulatorError> = .success([])
    var delay: Duration?
    var suspended: Set<SuspendableCall> = []
    var waiters: [SuspendableCall: [CheckedContinuation<Void, Never>]] = [:]
  }

  private let state: Mutex<State>

  public init(inventory: AndroidDeviceInventory = AndroidDeviceInventory(devices: [], creationOptions: .emptySample)) {
    self.state = Mutex(State(inventory: inventory))
  }

  /// 들어온 호출 순서대로. 멈춘 호출도 들어오는 즉시 기록된다.
  public var calls: [Call] {
    self.state.withLock { $0.calls }
  }

  /// 지금 저장된 목록 (`boot`·`create` 등이 바꾼 뒤의 값).
  public var inventory: AndroidDeviceInventory {
    self.state.withLock { $0.inventory }
  }

  public func fetchDevices() async throws(AndroidEmulatorError) -> AndroidDeviceInventory {
    self.record(.fetchDevices)
    await self.waitIfSuspended(.fetch)
    await self.sleepIfNeeded()
    let result: Result<AndroidDeviceInventory, AndroidEmulatorError> = self.state.withLock { state in
      if let error = state.fetchError {
        return .failure(error)
      }
      return .success(state.inventory)
    }
    return try result.get()
  }

  public func boot(_ id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) {
    self.record(.boot(id))
    await self.waitIfSuspended(.boot)
    await self.waitIfSuspended(.bootOf(id))
    await self.sleepIfNeeded()
    let result: Result<Void, AndroidEmulatorError> = self.state.withLock { state in
      if let error = state.bootErrors[id] ?? state.bootError {
        return .failure(error)
      }
      state.inventory = Self.inventory(state.inventory, setting: id, to: .booted)
      return .success(())
    }
    try result.get()
  }

  public func shutdown(_ id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) {
    self.record(.shutdown(id))
    await self.waitIfSuspended(.shutdown)
    await self.sleepIfNeeded()
    let result: Result<Void, AndroidEmulatorError> = self.state.withLock { state in
      if let error = state.shutdownError {
        return .failure(error)
      }
      state.inventory = Self.inventory(state.inventory, setting: id, to: .shutdown)
      return .success(())
    }
    try result.get()
  }

  public func create(
    displayName: String,
    image: AndroidSystemImageRef,
    profile: AndroidDeviceProfile.ID
  ) async throws(AndroidEmulatorError) -> AndroidVirtualDevice.ID {
    self.record(.create(displayName: displayName, image: image, profile: profile))
    await self.waitIfSuspended(.create)
    await self.sleepIfNeeded()
    let result: Result<AndroidVirtualDevice.ID, AndroidEmulatorError> = self.state.withLock { state in
      if let error = state.createError {
        return .failure(error)
      }
      if let problem = DeviceName.problem(in: displayName) {
        return .failure(.invalidDeviceName(problem))
      }
      let inventory = state.inventory
      guard
        inventory.creationOptions.contains(image: image, profile: profile),
        let chosenProfile = AndroidDeviceProfile.profile(profile)
      else {
        return .failure(.creationOptionUnavailable)
      }
      let normalized = DeviceName.normalized(displayName)
      let existing = Set(inventory.devices.map(\.id.rawValue))
      guard let name = AndroidAVDName.make(from: normalized, existing: existing) else {
        return .failure(.nameUnavailable)
      }
      let device = AndroidVirtualDevice(
        id: AndroidVirtualDevice.ID(name),
        displayName: normalized,
        systemImage: image,
        formFactor: chosenProfile.formFactor,
        state: .shutdown,
        availability: .available
      )
      state.inventory = AndroidDeviceInventory(
        devices: inventory.devices + [device],
        creationOptions: inventory.creationOptions
      )
      return .success(device.id)
    }
    return try result.get()
  }

  public func delete(_ id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) -> AndroidDeleteOutcome {
    self.record(.delete(id))
    await self.waitIfSuspended(.delete)
    await self.sleepIfNeeded()
    let result: Result<AndroidDeleteOutcome, AndroidEmulatorError> = self.state.withLock { state in
      if case .success = state.deleteResult {
        state.inventory = AndroidDeviceInventory(
          devices: state.inventory.devices.filter { $0.id != id },
          creationOptions: state.inventory.creationOptions
        )
      }
      return state.deleteResult
    }
    return try result.get()
  }

  public func erase(_ id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) {
    self.record(.erase(id))
    await self.waitIfSuspended(.erase)
    await self.sleepIfNeeded()
    if let error = self.state.withLock({ $0.eraseError }) {
      throw error
    }
  }

  public func deviceTraits(_ id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) -> AndroidDeviceTraits {
    self.record(.deviceTraits(id))
    await self.sleepIfNeeded()
    return try self.state.withLock { $0.deviceTraitsByDevice[id] ?? $0.deviceTraits }.get()
  }

  public func install(_ apk: URL, on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) {
    self.record(.install(apk, id))
    await self.waitIfSuspended(.install)
    await self.waitIfSuspended(.installOf(id))
    await self.sleepIfNeeded()
    if let error = self.state.withLock({ $0.installErrors[id] ?? $0.installError }) {
      throw error
    }
  }

  public func launch(_ package: AndroidPackageName, on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) {
    self.record(.launch(package, id))
    await self.sleepIfNeeded()
    if let error = self.state.withLock({ $0.launchErrors[id] ?? $0.launchError }) {
      throw error
    }
  }

  public func openURL(_ link: DeepLink, on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) {
    self.record(.openURL(link, id))
    await self.sleepIfNeeded()
    if let error = self.state.withLock({ $0.openURLError }) {
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
    _ inventory: AndroidDeviceInventory,
    setting id: AndroidVirtualDevice.ID,
    to newState: AndroidVirtualDevice.State
  ) -> AndroidDeviceInventory {
    let devices = inventory.devices.map { device in
      guard device.id == id else { return device }
      return AndroidVirtualDevice(
        id: device.id,
        displayName: device.displayName,
        systemImage: device.systemImage,
        formFactor: device.formFactor,
        state: newState,
        availability: device.availability
      )
    }
    return AndroidDeviceInventory(devices: devices, creationOptions: inventory.creationOptions)
  }
}

public extension AndroidEmulatorClientFake {
  func installedPackages(on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError)
    -> [AndroidPackageName]
  {
    self.record(.installedPackages(id))
    await self.waitIfSuspended(.packageList)
    await self.sleepIfNeeded()
    return try self.state.withLock { $0.installedPackages }.get()
  }

  /// 기록 → 멈춤 → 지연 → 설정한 에러면 던진다. 파일은 쓰지 않는다.
  func screenshot(on id: AndroidVirtualDevice.ID, to file: URL) async throws(AndroidEmulatorError) {
    self.record(.screenshot(id, file))
    await self.waitIfSuspended(.screenshot)
    await self.sleepIfNeeded()
    if let error = self.state.withLock({ $0.screenshotError }) {
      throw error
    }
  }

  /// 기록 → 멈춤 → 지연 → 스스로 끝나는 결과가 설정돼 있으면: 실패는 신호 없이 던지고(시작 실패 흉내), 성공은 (취소되지 않았으면)
  /// 신호를 보낸 뒤 곧바로 돌려준다. 아니면 아직 취소되지 않았고 신호를 보내기로 했으면 `onStarted` → 호출한 Task 가 취소될 때까지
  /// 기다림(이미 취소됐으면 바로) → 설정한 멈춘 뒤 결과, 없으면 신호를 보냈으면 `.saved`, 아니면 `.stoppedBeforeStart`.
  func recordScreen(
    on id: AndroidVirtualDevice.ID,
    to file: URL,
    onStarted: @escaping @Sendable () async -> Void
  ) async throws(AndroidEmulatorError) -> AndroidScreenRecordingResult {
    self.record(.recordScreen(id, file))
    await self.waitIfSuspended(.recording)
    await self.sleepIfNeeded()
    let (endsByItself, signals) = self.state.withLock { ($0.recordingEndsByItself, $0.recordingSignalsStart) }
    if case let .failure(error) = endsByItself {
      throw error
    }
    // 실제처럼 시작 전에 이미 취소됐으면 신호 없이 멈춘다.
    let signaled = !Task.isCancelled && signals
    if signaled {
      await onStarted()
    }
    if let endsByItself {
      return try endsByItself.get()
    }
    while !Task.isCancelled {
      try? await Task.sleep(for: .seconds(3600))
    }
    if let result = self.state.withLock({ $0.recordingResult }) {
      return try result.get()
    }
    return signaled ? .saved : .stoppedBeforeStart
  }
}

// 테스트가 결과·멈춤을 정하는 설정 메서드. `private` 상태(`state`)를 쓰므로 같은 파일에 둔다.
public extension AndroidEmulatorClientFake {
  func setInventory(_ inventory: AndroidDeviceInventory) {
    self.state.withLock { $0.inventory = inventory }
  }

  func setFetchError(_ error: AndroidEmulatorError?) {
    self.state.withLock { $0.fetchError = error }
  }

  /// 모든 기기의 `boot` 에러. 기기별 에러(`setBootError(_:for:)`)가 먼저다.
  func setBootError(_ error: AndroidEmulatorError?) {
    self.state.withLock { $0.bootError = error }
  }

  /// 이 기기의 `boot` 에러 (함께 켜기에서 일부만 실패하게 할 때).
  func setBootError(_ error: AndroidEmulatorError?, for id: AndroidVirtualDevice.ID) {
    self.state.withLock { $0.bootErrors[id] = error }
  }

  func setShutdownError(_ error: AndroidEmulatorError?) {
    self.state.withLock { $0.shutdownError = error }
  }

  /// 검사 전에 던질 `create` 에러.
  func setCreateError(_ error: AndroidEmulatorError?) {
    self.state.withLock { $0.createError = error }
  }

  /// `delete` 결과. 성공이면 그 기기를 목록에서 뺀다.
  func setDeleteResult(_ result: Result<AndroidDeleteOutcome, AndroidEmulatorError>) {
    self.state.withLock { $0.deleteResult = result }
  }

  func setEraseError(_ error: AndroidEmulatorError?) {
    self.state.withLock { $0.eraseError = error }
  }

  /// Example 용. 모든 호출이 결과를 내기 전에 이만큼 기다린다 (`nil` 이면 바로).
  func setDelay(_ delay: Duration?) {
    self.state.withLock { $0.delay = delay }
  }

  /// 이후 `fetchDevices()` 가 기록만 하고 `resumeFetches()` 까지 기다린다.
  func suspendFetches() {
    self.suspend(.fetch)
  }

  /// 기다리는 `fetchDevices()` 를 모두 깨우고, 이후 호출은 기다리지 않는다.
  func resumeFetches() {
    self.resume(.fetch)
  }

  /// 이후 `boot(_:)` 가 기록만 하고 `resumeBoots()` 까지 기다린다.
  func suspendBoots() {
    self.suspend(.boot)
  }

  func resumeBoots() {
    self.resume(.boot)
  }

  /// 이후 이 기기의 `boot(_:)` 만 기록하고 `resumeBoot(of:)` 까지 기다린다 (다른 기기는 기다리지 않는다).
  func suspendBoot(of id: AndroidVirtualDevice.ID) {
    self.suspend(.bootOf(id))
  }

  func resumeBoot(of id: AndroidVirtualDevice.ID) {
    self.resume(.bootOf(id))
  }

  func suspendShutdowns() {
    self.suspend(.shutdown)
  }

  func resumeShutdowns() {
    self.resume(.shutdown)
  }

  func suspendCreates() {
    self.suspend(.create)
  }

  func resumeCreates() {
    self.resume(.create)
  }

  func suspendDeletes() {
    self.suspend(.delete)
  }

  func resumeDeletes() {
    self.resume(.delete)
  }

  func suspendErases() {
    self.suspend(.erase)
  }

  func resumeErases() {
    self.resume(.erase)
  }

  /// `deviceTraits` 결과.
  func setDeviceTraits(_ result: Result<AndroidDeviceTraits, AndroidEmulatorError>) {
    self.state.withLock { $0.deviceTraits = result }
  }

  func setInstallError(_ error: AndroidEmulatorError?) {
    self.state.withLock { $0.installError = error }
  }

  func setLaunchError(_ error: AndroidEmulatorError?) {
    self.state.withLock { $0.launchError = error }
  }

  func setOpenURLError(_ error: AndroidEmulatorError?) {
    self.state.withLock { $0.openURLError = error }
  }

  /// `installedPackages` 결과 (그대로 돌려준다. 정렬하지 않는다).
  func setInstalledPackages(_ result: Result<[AndroidPackageName], AndroidEmulatorError>) {
    self.state.withLock { $0.installedPackages = result }
  }

  /// 이후 `install(_:on:)` 이 기록만 하고 `resumeInstalls()` 까지 기다린다.
  func suspendInstalls() {
    self.suspend(.install)
  }

  func resumeInstalls() {
    self.resume(.install)
  }

  /// 이 기기의 `deviceTraits` 결과 (여러 기기 설치에서 기기마다 다르게). nil 이면 전체 설정을 쓴다.
  func setDeviceTraits(_ result: Result<AndroidDeviceTraits, AndroidEmulatorError>?, for id: AndroidVirtualDevice.ID) {
    self.state.withLock { $0.deviceTraitsByDevice[id] = result }
  }

  /// 이 기기의 `install` 에러. 전체 에러(`setInstallError(_:)`)보다 먼저다.
  func setInstallError(_ error: AndroidEmulatorError?, for id: AndroidVirtualDevice.ID) {
    self.state.withLock { $0.installErrors[id] = error }
  }

  /// 이 기기의 `launch` 에러. 전체 에러(`setLaunchError(_:)`)보다 먼저다.
  func setLaunchError(_ error: AndroidEmulatorError?, for id: AndroidVirtualDevice.ID) {
    self.state.withLock { $0.launchErrors[id] = error }
  }

  /// 이후 이 기기의 `install(_:on:)` 만 기록하고 `resumeInstall(of:)` 까지 기다린다 (다른 기기는 기다리지 않는다).
  func suspendInstall(of id: AndroidVirtualDevice.ID) {
    self.suspend(.installOf(id))
  }

  func resumeInstall(of id: AndroidVirtualDevice.ID) {
    self.resume(.installOf(id))
  }

  func setScreenshotError(_ error: AndroidEmulatorError?) {
    self.state.withLock { $0.screenshotError = error }
  }

  /// 이후 `screenshot(on:to:)` 가 기록만 하고 `resumeScreenshots()` 까지 기다린다.
  func suspendScreenshots() {
    self.suspend(.screenshot)
  }

  func resumeScreenshots() {
    self.resume(.screenshot)
  }

  /// 설정하면 이후 `recordScreen` 이 취소로 멈춘 뒤 이 결과를 낸다 (실패면 던진다). nil 이면 신호를 보냈으면 `.saved`,
  /// 아니면 `.stoppedBeforeStart`.
  func setRecordingResult(_ result: Result<AndroidScreenRecordingResult, AndroidEmulatorError>?) {
    self.state.withLock { $0.recordingResult = result }
  }

  /// 설정하면 이후 `recordScreen` 이 취소를 기다리지 않고 끝난다: 성공은 시작 신호 뒤 그 값(예: `.savedAtTimeLimit`), 실패는 신호 없이
  /// 그 에러(시작 실패·기기 꺼짐 흉내). nil 이면 취소까지 기다린다.
  func setRecordingEndsByItself(_ result: Result<AndroidScreenRecordingResult, AndroidEmulatorError>?) {
    self.state.withLock { $0.recordingEndsByItself = result }
  }

  /// false 면 이후 `recordScreen` 이 시작 신호(`onStarted`)를 보내지 않는다 (기본 true).
  func setRecordingSignalsStart(_ signals: Bool) {
    self.state.withLock { $0.recordingSignalsStart = signals }
  }

  /// 이후 `recordScreen` 이 기록만 하고 `resumeRecordings()` 까지 기다린다 (시작 신호 전, 취소를 받지 않는다).
  func suspendRecordings() {
    self.suspend(.recording)
  }

  func resumeRecordings() {
    self.resume(.recording)
  }

  /// 이후 `installedPackages(on:)` 이 기록만 하고 `resumePackageLists()` 까지 기다린다.
  func suspendPackageLists() {
    self.suspend(.packageList)
  }

  func resumePackageLists() {
    self.resume(.packageList)
  }
}
