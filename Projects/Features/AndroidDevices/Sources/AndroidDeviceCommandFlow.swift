import AndroidEmulatorInterface
import Core

/// 기기 명령 흐름: 켜기·끄기·만들기·삭제·초기화. 명령이 실패하면 알림을 쌓고(취소는 Model 의 창구가 거른다), 끝나면 목록을 다시
/// 읽는다 (만들기만 다시 읽지 않고 Model 에 맡긴다). iOS `DeviceCommandFlow` 와 같은 역할이다.
/// `AndroidDevicesModel` 이 `private` 으로 소유하고, 진행 기록(`activity`·`isCreating`)을 시작한 Model 메서드 안에서만 부른다.
/// Model 상태를 직접 바꾸지 않는다 (바꾸는 것은 `AndroidAppInstallFlow.Host` 창구로만, 부를 때 넘겨받는다).
@MainActor
struct AndroidDeviceCommandFlow {
  let emulator: any AndroidEmulatorClient

  /// 켜고(부팅 완료까지) 실패면 에러를 돌려준다. 알림·다시 읽기는 부르는 쪽이 한다 (함께 켜기가 결과를 모은다).
  func boot(_ id: AndroidVirtualDevice.ID) async -> AndroidEmulatorError? {
    do throws(AndroidEmulatorError) {
      try await self.emulator.boot(id)
      return nil
    } catch {
      return error
    }
  }

  /// 켜고, 실패하면 알림을 쌓은 뒤, 결과와 관계없이 다시 읽는다 (행 켜기·한 대 함께 켜기).
  func bootAndReport(_ device: AndroidVirtualDevice, host: AndroidAppInstallFlow.Host) async {
    if let error = await self.boot(device.id) {
      host.enqueue(.bootFailed(AndroidDeviceLabel(device), error))
    }
    await host.reload()
  }

  func shutdown(_ device: AndroidVirtualDevice, host: AndroidAppInstallFlow.Host) async {
    do throws(AndroidEmulatorError) {
      try await self.emulator.shutdown(device.id)
    } catch {
      host.enqueue(.shutdownFailed(AndroidDeviceLabel(device), error))
    }
    await host.reload()
  }

  /// 기기를 만들고 새 기기의 id 를 돌려준다. 실패하면 알림을 쌓고 nil. **다시 읽지 않는다**: Model 이 새 기기를 고른 다음
  /// 다시 읽어야 다시 읽기가 목록에 있는 선택으로 남긴다.
  func create(
    name: String,
    image: AndroidSystemImageRef,
    profile: AndroidDeviceProfile.ID,
    label: AndroidDeviceLabel,
    host: AndroidAppInstallFlow.Host
  ) async -> AndroidVirtualDevice.ID? {
    do throws(AndroidEmulatorError) {
      return try await self.emulator.create(displayName: name, image: image, profile: profile)
    } catch {
      host.enqueue(.createFailed(label, error))
      return nil
    }
  }

  /// 확인한 삭제·초기화를 실행하고 다시 읽는다. 실패하면 알림을, 삭제가 기기 폴더를 남겼으면 정보 알림을 쌓는다.
  func deleteOrErase(
    _ confirmation: AndroidDeviceConfirmation,
    device: AndroidVirtualDevice,
    host: AndroidAppInstallFlow.Host
  ) async {
    do throws(AndroidEmulatorError) {
      switch confirmation.action {
      case .delete:
        if case let .folderKept(folder) = try await self.emulator.delete(device.id) {
          host.enqueue(.folderKept(confirmation.device, folder))
        }
      case .erase:
        try await self.emulator.erase(device.id)
      }
    } catch {
      host.enqueue(confirmation.failedNotice(error))
    }
    await host.reload()
  }
}
