import Core
import SimulatorInterface

/// 기기 명령 흐름: 끄기·만들기·삭제·초기화. 명령이 실패하면 알림을 쌓고, 끝나면 목록을 다시 읽는다.
/// `LauncherModel` 이 `private` 으로 소유하고, 진행 기록(`activity`·`isCreating`)을 시작한 Model 메서드 안에서만 부른다.
/// Model 상태를 직접 바꾸지 않는다 (바꾸는 것은 `AppInstallFlow.Host` 창구로만, 부를 때 넘겨받는다).
@MainActor
struct DeviceCommandFlow {
  let simulator: any SimulatorClient

  func shutdown(_ device: VirtualDevice, host: AppInstallFlow.Host) async {
    let label = LauncherNotice.Device(device)
    do throws(SimulatorError) {
      try await self.simulator.shutdown(device.id)
    } catch {
      host.enqueue(.shutdownFailed(label, error))
    }
    await host.reload()
  }

  func create(
    name: String,
    deviceType: DeviceType.ID,
    runtime: DeviceRuntime,
    host: AppInstallFlow.Host
  ) async {
    let label = LauncherNotice.Device(name: name, runtimeName: runtime.name)
    do throws(SimulatorError) {
      _ = try await self.simulator.create(name: name, deviceType: deviceType, runtime: runtime.id)
    } catch {
      host.enqueue(.createFailed(label, error))
    }
    await host.reload()
  }

  func run(_ confirmation: DeviceConfirmation, on id: VirtualDevice.ID, host: AppInstallFlow.Host) async {
    do throws(SimulatorError) {
      switch confirmation.action {
      case .delete: try await self.simulator.delete(id)
      case .erase: try await self.simulator.erase(id)
      }
    } catch {
      host.enqueue(confirmation.failedNotice(error))
    }
    await host.reload()
  }
}
