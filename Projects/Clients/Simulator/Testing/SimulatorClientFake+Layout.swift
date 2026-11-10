import Core
import SimulatorInterface

// MARK: - 실행 중인 앱 목록·앱 지우기 (iOS 레이아웃 보기가 쓴다)

public extension SimulatorClientFake {
  /// 이 기기의 `runningApplications(on:)` 결과. 설정하지 않은 기기는 빈 목록이다. 다른 호출은 이 목록을 바꾸지 않는다.
  func setRunningApplications(_ bundleIDs: [AppBundleID], for id: VirtualDevice.ID) {
    self.state.withLock { $0.runningApplications[id] = bundleIDs }
  }

  func setRunningApplicationsError(_ error: SimulatorError?) {
    self.state.withLock { $0.runningApplicationsError = error }
  }

  /// 이후 `runningApplications(on:)` 이 기록만 하고 `resumeRunningApplications()` 까지 기다린다.
  func suspendRunningApplications() {
    self.suspend(.runningApplications)
  }

  /// 기다리는 `runningApplications(on:)` 을 모두 깨우고, 이후 호출은 기다리지 않는다.
  func resumeRunningApplications() {
    self.resume(.runningApplications)
  }

  /// `install(_:on:)` 과 같은 순서로 기록·멈춤·지연·에러·기기 상태를 보고, 설정한 목록을 그대로 돌려준다 (정렬·거르기 하지 않는다).
  func runningApplications(on id: VirtualDevice.ID) async throws(SimulatorError) -> [AppBundleID] {
    self.record(.runningApplications(id))
    await self.waitIfSuspended(.runningApplications)
    await self.sleepIfNeeded()
    if let error = self.bootedDeviceError(id, configured: \.runningApplicationsError) {
      throw error
    }
    return self.state.withLock { $0.runningApplications[id] ?? [] }
  }

  func setUninstallError(_ error: SimulatorError?) {
    self.state.withLock { $0.uninstallError = error }
  }

  /// 이후 `uninstall(_:on:)` 이 기록만 하고 `resumeUninstalls()` 까지 기다린다.
  func suspendUninstalls() {
    self.suspend(.uninstall)
  }

  /// 기다리는 `uninstall(_:on:)` 을 모두 깨우고, 이후 호출은 기다리지 않는다.
  func resumeUninstalls() {
    self.resume(.uninstall)
  }

  /// `install(_:on:)` 과 같은 순서로 기록·멈춤·지연·에러·기기 상태를 본다 (꺼진 기기는 `.deviceNotBooted`).
  /// 설치 여부는 보지 않고, 성공해도 설치된 앱·실행 중 앱 목록은 바꾸지 않는다.
  func uninstall(_ bundleID: AppBundleID, on id: VirtualDevice.ID) async throws(SimulatorError) {
    self.record(.uninstall(bundleID, id))
    await self.waitIfSuspended(.uninstall)
    await self.sleepIfNeeded()
    if let error = self.bootedDeviceError(id, configured: \.uninstallError) {
      throw error
    }
  }
}
