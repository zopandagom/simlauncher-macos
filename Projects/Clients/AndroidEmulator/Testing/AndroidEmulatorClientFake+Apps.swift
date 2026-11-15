import AndroidEmulatorInterface
import Core

/// 설치된 앱 관리(`uninstall`)의 Fake 동작과 설정 메서드.
/// 다른 앱 작업과 같이 목록·기기 상태를 보지 않고 설정한 결과만 돌려준다. 성공해도 `installedPackages` 결과를 바꾸지 않는다
/// (iOS `SimulatorClientFake.uninstall` 과 같다. 테스트가 `setInstalledPackages` 로 다시 정한다).
public extension AndroidEmulatorClientFake {
  /// 설치된 앱 관리 호출 (`Call.appManagement`).
  enum AppManagementCall: Hashable, Sendable {
    case uninstall(AndroidPackageName, AndroidVirtualDevice.ID)
  }

  /// 설정하면 이후 `uninstall(_:on:)` 이 이 에러를 던진다. nil(기본)이면 성공.
  func setUninstallError(_ error: AndroidEmulatorError?) {
    self.state.withLock { $0.apps.uninstallError = error }
  }

  /// 이후 `uninstall(_:on:)` 이 기록만 하고 `resumeUninstalls()` 까지 기다린다.
  func suspendUninstalls() {
    self.suspend(.uninstall)
  }

  /// 기다리는 `uninstall(_:on:)` 을 모두 깨우고, 이후 호출은 기다리지 않는다.
  func resumeUninstalls() {
    self.resume(.uninstall)
  }

  /// 기록 → 멈춤 → 지연 → 설정한 에러면 던진다.
  func uninstall(_ package: AndroidPackageName, on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) {
    self.record(.appManagement(.uninstall(package, id)))
    await self.waitIfSuspended(.uninstall)
    await self.sleepIfNeeded()
    if let error = self.state.withLock({ $0.apps.uninstallError }) {
      throw error
    }
  }
}

/// 설치된 앱 관리 Fake 상태 (`AndroidEmulatorClientFake.State.apps`).
struct AndroidAppManagementState {
  var uninstallError: AndroidEmulatorError?
}
