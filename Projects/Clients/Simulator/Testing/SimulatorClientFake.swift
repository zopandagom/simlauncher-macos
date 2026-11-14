import Core
import Foundation
import SimulatorInterface
import Synchronization

/// 테스트·Example 용 `SimulatorClient`. 호출을 기록하고, 결과·에러·지연·멈춤을 바꿀 수 있다.
/// boot 가 성공하면 그 기기를 `.booted`, shutdown 이 성공하면 `.shutdown` 으로 바꾼 목록을 저장한다.
/// create 가 성공하면 꺼진 새 기기를 목록 끝에 더하고, delete 가 성공하면 그 기기를 뺀다. 꺼짐 여부는 검사하지 않는다.
/// 목록을 다시 만들 때 런타임·기기 종류는 그대로 둔다.
/// install·openURL 은 실제처럼 목록의 기기 상태를 본다(없으면 `.deviceNotFound`, 켜져 있지 않으면 `.deviceNotBooted`),
/// 성공해도 목록은 바꾸지 않는다. screenshot·recordVideo 도 install 과 같은 순서로 기기 상태를 보고, 파일은 만들지 않는다
/// (screenshot 은 `setScreenshotPNG` 로 바이트를 정하면 그것을 파일에 쓴다).
/// recordVideo 는 기본으로 바로 시작 신호를 보내고 호출한 Task 가 취소될 때까지 기다린 뒤 `.saved` 를 돌려준다. launch 는 설치 여부를 보지 않고 설정한 에러가 없으면 성공한다.
/// launchWithConsole 은 처리기(`setConsoleHandler`)가 없으면 launch 의 에러를 던지거나, `.launched` 를 보내고 호출한 Task 가 취소될 때까지 기다린 뒤
/// `.stopped`.
/// installedApps 도 install 과 같은 순서로 기기 상태를 보고, 기기별로 설정한 앱 목록(기본 빈 목록)을 그대로 돌려준다.
/// runningApplications·uninstall 과 테스트 조건(displaySettings·setDisplaySetting·simulateLocation)도 같은 순서로 기기 상태를 본다
/// (`SimulatorClientFake+Layout.swift`·`+Conditions.swift`).
/// 런타임 이미지 목록은 기기 목록과 따로 저장하고(기본값 `RuntimeImage.samples`), 어떤 호출도 그 목록을 바꾸지 않는다.
public final class SimulatorClientFake: SimulatorClient {
  public enum Call: Hashable, Sendable {
    case fetchInventory
    case fetchRuntimeImages
    case boot(VirtualDevice.ID)
    case shutdown(VirtualDevice.ID)
    case openSimulatorApp
    case create(name: String, deviceType: DeviceType.ID, runtime: DeviceRuntime.ID)
    case delete(VirtualDevice.ID)
    case erase(VirtualDevice.ID)
    case install(URL, VirtualDevice.ID)
    case installedApps(VirtualDevice.ID)
    case launch(AppBundleID, VirtualDevice.ID)
    case launchWithConsole(AppBundleID, VirtualDevice.ID)
    case openURL(DeepLink, VirtualDevice.ID)
    case screenshot(VirtualDevice.ID, URL)
    case recordVideo(VirtualDevice.ID, URL)
    case runningApplications(VirtualDevice.ID)
    case uninstall(AppBundleID, VirtualDevice.ID)
    case testCondition(ConditionCall)
  }

  enum SuspendableCall: Hashable {
    case fetch, boot, create, delete, erase, install, installedApps, openURL, screenshot, recordVideo
    case runningApplications, uninstall, conditions, conditionReads
    case bootOf(VirtualDevice.ID)
  }

  struct State {
    var inventory: DeviceInventory
    var runtimeImages: [RuntimeImage] = RuntimeImage.samples
    var calls: [Call] = []
    var fetchError: SimulatorError?
    var runtimeImagesError: SimulatorError?
    var bootError: SimulatorError?
    var shutdownError: SimulatorError?
    var openAppError: SimulatorError?
    var createError: SimulatorError?
    var deleteError: SimulatorError?
    var eraseError: SimulatorError?
    var installError: SimulatorError?
    var installedApps: [VirtualDevice.ID: [InstalledApp]] = [:]
    var installedAppsError: SimulatorError?
    var launchError: SimulatorError?
    var consoleHandler: ConsoleHandler?
    var openURLError: SimulatorError?
    var screenshotError: SimulatorError?
    var screenshotPNG: Data?
    var runningApplications: [VirtualDevice.ID: [AppBundleID]] = [:]
    var runningApplicationsError: SimulatorError?
    var uninstallError: SimulatorError?
    var conditions = SimulatorConditionState()
    var recordingStartError: SimulatorError?
    var recordingStopOutcome: Result<ScreenRecordingResult, SimulatorError>?
    var recordingSignalsStart = true
    var delay: Duration?
    var createdCount = 0
    var suspended: Set<SuspendableCall> = []
    var waiters: [SuspendableCall: [CheckedContinuation<Void, Never>]] = [:]
  }

  let state: Mutex<State>

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

  /// 이후 이 기기의 `boot(_:)` 만 기록하고 `resumeBoot(of:)` 까지 기다린다 (다른 기기는 기다리지 않는다).
  public func suspendBoot(of id: VirtualDevice.ID) {
    self.suspend(.bootOf(id))
  }

  /// 기다리는 이 기기의 `boot(_:)` 를 깨우고, 이후 호출은 기다리지 않는다.
  public func resumeBoot(of id: VirtualDevice.ID) {
    self.resume(.bootOf(id))
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
    await self.waitIfSuspended(.bootOf(id))
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

  func record(_ call: Call) {
    self.state.withLock { $0.calls.append(call) }
  }

  func sleepIfNeeded() async {
    if let delay = self.state.withLock({ $0.delay }) {
      try? await Task.sleep(for: delay)
    }
  }

  func suspend(_ call: SuspendableCall) {
    self.state.withLock { _ = $0.suspended.insert(call) }
  }

  func resume(_ call: SuspendableCall) {
    let waiters = self.state.withLock { state in
      state.suspended.remove(call)
      return state.waiters.removeValue(forKey: call) ?? []
    }
    for waiter in waiters {
      waiter.resume()
    }
  }

  func waitIfSuspended(_ call: SuspendableCall) async {
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

// MARK: - 앱 설치·목록·실행·링크 열기·스크린샷·녹화

public extension SimulatorClientFake {
  func setInstallError(_ error: SimulatorError?) {
    self.state.withLock { $0.installError = error }
  }

  func setLaunchError(_ error: SimulatorError?) {
    self.state.withLock { $0.launchError = error }
  }

  /// 이후 `install(_:on:)` 이 기록만 하고 `resumeInstalls()` 까지 기다린다.
  func suspendInstalls() {
    self.suspend(.install)
  }

  /// 기다리는 `install(_:on:)` 을 모두 깨우고, 이후 호출은 기다리지 않는다.
  func resumeInstalls() {
    self.resume(.install)
  }

  /// 기록 → 멈춤 → 지연 → 설정된 에러면 던짐 → 목록에 기기가 없으면 `.deviceNotFound`, `.booted` 가 아니면 `.deviceNotBooted`.
  /// Model 이 켜기를 빠뜨리면 테스트가 잡도록 실제처럼 상태를 본다. 성공해도 목록은 바꾸지 않는다.
  func install(_ app: URL, on id: VirtualDevice.ID) async throws(SimulatorError) {
    self.record(.install(app, id))
    await self.waitIfSuspended(.install)
    await self.sleepIfNeeded()
    if let error = self.bootedDeviceError(id, configured: \.installError) {
      throw error
    }
  }

  /// 이 기기의 `installedApps(on:)` 결과. 설정하지 않은 기기는 빈 목록이다. 설치·실행 호출은 이 목록을 바꾸지 않는다.
  func setInstalledApps(_ apps: [InstalledApp], on id: VirtualDevice.ID) {
    self.state.withLock { $0.installedApps[id] = apps }
  }

  func setInstalledAppsError(_ error: SimulatorError?) {
    self.state.withLock { $0.installedAppsError = error }
  }

  /// 이후 `installedApps(on:)` 이 기록만 하고 `resumeInstalledApps()` 까지 기다린다.
  func suspendInstalledApps() {
    self.suspend(.installedApps)
  }

  /// 기다리는 `installedApps(on:)` 을 모두 깨우고, 이후 호출은 기다리지 않는다.
  func resumeInstalledApps() {
    self.resume(.installedApps)
  }

  /// `install(_:on:)` 과 같은 순서로 기록·멈춤·지연·에러·기기 상태를 보고, 설정한 목록을 그대로 돌려준다 (정렬하지 않는다).
  func installedApps(on id: VirtualDevice.ID) async throws(SimulatorError) -> [InstalledApp] {
    self.record(.installedApps(id))
    await self.waitIfSuspended(.installedApps)
    await self.sleepIfNeeded()
    if let error = self.bootedDeviceError(id, configured: \.installedAppsError) {
      throw error
    }
    return self.state.withLock { $0.installedApps[id] ?? [] }
  }

  /// 기록 → 지연 → 설정된 에러면 던짐 → 성공. 설치 여부는 보지 않는다.
  func launch(_ bundleID: AppBundleID, on id: VirtualDevice.ID) async throws(SimulatorError) {
    self.record(.launch(bundleID, id))
    await self.sleepIfNeeded()
    if let error = self.state.withLock({ $0.launchError }) {
      throw error
    }
  }

  /// `launchWithConsole` 처리기. `emit` 으로 알림을 넘기고(호출한 쪽의 `onEvent` 가 끝난 뒤 돌아온다) 끝을 정한다.
  /// 멈춤 흉내는 처리기가 호출한 Task 의 취소를 보고 `.stopped` 를 돌려주는 식으로 한다.
  typealias ConsoleHandler = @Sendable (
    AppBundleID,
    VirtualDevice.ID,
    _ emit: @escaping @Sendable (AppConsoleEvent) async -> Void
  ) async throws(SimulatorError) -> AppConsoleEnd

  /// 이후 `launchWithConsole` 의 처리기. nil 이면 기본 동작 (타입 설명).
  func setConsoleHandler(_ handler: ConsoleHandler?) {
    self.state.withLock { $0.consoleHandler = handler }
  }

  /// 기록 → 지연 → 처리기가 있으면 그 결과. 없으면 설정한 launch 에러를 던지거나, 아직 취소되지 않았으면 `.launched` 를 보내고
  /// 호출한 Task 가 취소될 때까지 기다린 뒤 `.stopped`. 설치 여부·기기 상태는 보지 않는다 (launch 와 같다).
  func launchWithConsole(
    _ bundleID: AppBundleID,
    on id: VirtualDevice.ID,
    onEvent: @escaping @Sendable (AppConsoleEvent) async -> Void
  ) async throws(SimulatorError) -> AppConsoleEnd {
    self.record(.launchWithConsole(bundleID, id))
    await self.sleepIfNeeded()
    let (handler, error) = self.state.withLock { ($0.consoleHandler, $0.launchError) }
    if let handler {
      return try await handler(bundleID, id, onEvent)
    }
    if let error {
      throw error
    }
    if !Task.isCancelled {
      await onEvent(.launched)
    }
    while !Task.isCancelled {
      try? await Task.sleep(for: .seconds(3600))
    }
    return .stopped
  }

  func setOpenURLError(_ error: SimulatorError?) {
    self.state.withLock { $0.openURLError = error }
  }

  /// 이후 `openURL(_:on:)` 이 기록만 하고 `resumeOpenURLs()` 까지 기다린다.
  func suspendOpenURLs() {
    self.suspend(.openURL)
  }

  /// 기다리는 `openURL(_:on:)` 을 모두 깨우고, 이후 호출은 기다리지 않는다.
  func resumeOpenURLs() {
    self.resume(.openURL)
  }

  /// `install(_:on:)` 과 같은 순서로 기록·멈춤·지연·에러·기기 상태를 본다. 성공해도 목록은 바꾸지 않는다.
  func openURL(_ link: DeepLink, on id: VirtualDevice.ID) async throws(SimulatorError) {
    self.record(.openURL(link, id))
    await self.waitIfSuspended(.openURL)
    await self.sleepIfNeeded()
    if let error = self.bootedDeviceError(id, configured: \.openURLError) {
      throw error
    }
  }

  func setScreenshotError(_ error: SimulatorError?) {
    self.state.withLock { $0.screenshotError = error }
  }

  /// 설정하면 이후 성공한 `screenshot(on:to:)` 가 이 바이트를 `file` 에 쓴다 (쓰지 못하면 `.commandFailed`). nil(기본)이면 파일을 만들지 않는다.
  func setScreenshotPNG(_ data: Data?) {
    self.state.withLock { $0.screenshotPNG = data }
  }

  /// 이후 `screenshot(on:to:)` 가 기록만 하고 `resumeScreenshots()` 까지 기다린다.
  func suspendScreenshots() {
    self.suspend(.screenshot)
  }

  /// 기다리는 `screenshot(on:to:)` 를 모두 깨우고, 이후 호출은 기다리지 않는다.
  func resumeScreenshots() {
    self.resume(.screenshot)
  }

  /// `install(_:on:)` 과 같은 순서로 기록·멈춤·지연·에러·기기 상태를 본다. 성공하면 `setScreenshotPNG` 바이트를 파일에 쓰고
  /// (설정하지 않았으면 파일을 만들지 않는다), 목록은 바꾸지 않는다.
  func screenshot(on id: VirtualDevice.ID, to file: URL) async throws(SimulatorError) {
    self.record(.screenshot(id, file))
    await self.waitIfSuspended(.screenshot)
    await self.sleepIfNeeded()
    if let error = self.bootedDeviceError(id, configured: \.screenshotError) {
      throw error
    }
    guard let png = self.state.withLock({ $0.screenshotPNG }) else { return }
    do {
      try png.write(to: file)
    } catch {
      throw .commandFailed
    }
  }

  /// 설정하면 이후 `recordVideo` 가 시작 신호 없이 이 에러를 던진다 (시작 실패 흉내). nil 이면 기기 상태만 본다.
  func setRecordingStartError(_ error: SimulatorError?) {
    self.state.withLock { $0.recordingStartError = error }
  }

  /// 설정하면 이후 `recordVideo` 가 멈춘 뒤 이 결과를 낸다 (실패면 던진다). nil 이면 시작 신호를 보냈으면 `.saved`,
  /// 아니면 `.stoppedBeforeStart`.
  func setRecordingStopOutcome(_ outcome: Result<ScreenRecordingResult, SimulatorError>?) {
    self.state.withLock { $0.recordingStopOutcome = outcome }
  }

  /// false 면 이후 `recordVideo` 가 시작 신호(`onStarted`)를 보내지 않는다 (기본 true).
  func setRecordingSignalsStart(_ signals: Bool) {
    self.state.withLock { $0.recordingSignalsStart = signals }
  }

  /// 이후 `recordVideo` 가 기록만 하고 `resumeRecordings()` 까지 기다린다 (시작 신호 전).
  func suspendRecordings() {
    self.suspend(.recordVideo)
  }

  /// 기다리는 `recordVideo` 를 모두 깨우고, 이후 호출은 기다리지 않는다.
  func resumeRecordings() {
    self.resume(.recordVideo)
  }

  /// 기록 → 멈춤 → 지연 → 설정된 시작 에러·기기 상태(`install(_:on:)` 과 같은 순서)면 던짐 → 아직 취소되지 않았고
  /// 신호를 보내기로 했으면 `onStarted` → 호출한 Task 가 취소될 때까지 기다림(이미 취소됐으면 바로) → 설정한 멈춘 뒤 결과,
  /// 없으면 신호를 보냈으면 `.saved`, 아니면 `.stoppedBeforeStart`. 파일은 만들지 않고 목록은 바꾸지 않는다.
  func recordVideo(
    on id: VirtualDevice.ID,
    to file: URL,
    onStarted: @escaping @Sendable () async -> Void
  ) async throws(SimulatorError) -> ScreenRecordingResult {
    self.record(.recordVideo(id, file))
    await self.waitIfSuspended(.recordVideo)
    await self.sleepIfNeeded()
    if let error = self.bootedDeviceError(id, configured: \.recordingStartError) {
      throw error
    }
    // 실제처럼 시작 전에 이미 취소됐으면 신호 없이 멈춘다.
    let signaled = !Task.isCancelled && self.state.withLock { $0.recordingSignalsStart }
    if signaled {
      await onStarted()
    }
    while !Task.isCancelled {
      try? await Task.sleep(for: .seconds(3600))
    }
    if let outcome = self.state.withLock({ $0.recordingStopOutcome }) {
      return try outcome.get()
    }
    return signaled ? .saved : .stoppedBeforeStart
  }

  /// 설정한 에러, 없으면 목록의 기기 상태: 없으면 `.deviceNotFound`, `.booted` 가 아니면 `.deviceNotBooted`.
  internal func bootedDeviceError(
    _ id: VirtualDevice.ID,
    configured: KeyPath<State, SimulatorError?>
  ) -> SimulatorError? {
    self.state.withLock { state in
      if let error = state[keyPath: configured] {
        return error
      }
      guard let device = state.inventory.devices.first(where: { $0.id == id }) else {
        return .deviceNotFound
      }
      return device.state == .booted ? nil : .deviceNotBooted
    }
  }
}

// MARK: - 런타임 이미지

public extension SimulatorClientFake {
  func setRuntimeImages(_ images: [RuntimeImage]) {
    self.state.withLock { $0.runtimeImages = images }
  }

  func setRuntimeImagesError(_ error: SimulatorError?) {
    self.state.withLock { $0.runtimeImagesError = error }
  }

  /// 기록 → 지연 → 설정된 에러면 던짐 → 저장된 목록 (설정한 순서 그대로).
  func fetchRuntimeImages() async throws(SimulatorError) -> [RuntimeImage] {
    self.record(.fetchRuntimeImages)
    await self.sleepIfNeeded()
    let result: Result<[RuntimeImage], SimulatorError> = self.state.withLock { state in
      if let error = state.runtimeImagesError {
        return .failure(error)
      }
      return .success(state.runtimeImages)
    }
    return try result.get()
  }
}
