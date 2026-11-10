import Core
import SimulatorInterface

/// 기기 명령 흐름: 끄기·만들기·삭제·초기화. 명령이 실패하면 알림을 쌓고, 끝나면 목록을 다시 읽는다.
/// 끄기는 앞뒤로 `hooks.willShutDown`·`didShutDown` 을 기다려 부르고(실패해도 `didShutDown`), 목록을 읽으면 Model 이
/// `devicesListed(_:)` 로 켜진 기기를 `hooks.listed` 에 알린다 (App 이 레이아웃 러너 정리에 잇는다, `LauncherDeviceHooks`).
/// `LauncherModel` 이 `private` 으로 소유하고, 진행 기록(`activity`·`isCreating`)을 시작한 Model 메서드 안에서만 부른다.
/// Model 상태를 직접 바꾸지 않는다 (바꾸는 것은 `AppInstallFlow.Host` 창구로만, 부를 때 넘겨받는다).
@MainActor
struct DeviceCommandFlow {
  let simulator: any SimulatorClient
  let hooks: LauncherDeviceHooks

  func shutdown(_ device: VirtualDevice, host: AppInstallFlow.Host) async {
    let label = LauncherNotice.Device(device)
    await self.hooks.willShutDown(device.id)
    do throws(SimulatorError) {
      try await self.simulator.shutdown(device.id)
    } catch {
      host.enqueue(.shutdownFailed(label, error))
    }
    await self.hooks.didShutDown(device.id)
    await host.reload()
  }

  /// 읽은 목록의 켜진 기기 ID 집합을 `hooks.listed` 에 알린다 (꺼진·켜는 중 기기는 빠진다). 기다리지 않는다.
  func devicesListed(_ list: DeviceList) {
    let booted = list.sections.flatMap(\.devices).filter { $0.state == .booted }.map(\.id)
    self.hooks.listed(Set(booted))
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
