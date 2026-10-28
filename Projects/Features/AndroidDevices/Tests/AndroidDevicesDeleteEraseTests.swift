import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 삭제·초기화 확인과 실행.
@MainActor
struct AndroidDevicesDeleteEraseTests: AndroidDevicesTesting {
  private let phone = AndroidVirtualDevice.phoneSample.id
  private let tablet = AndroidVirtualDevice.bootedTabletSample.id
  private let unsupported = AndroidVirtualDevice.unsupportedNameSample.id

  private func confirmation(
    _ action: AndroidDeviceConfirmation.Action,
    _ device: AndroidVirtualDevice
  ) -> AndroidDeviceConfirmation {
    AndroidDeviceConfirmation(action: action, deviceID: device.id, device: AndroidDeviceLabel(device))
  }

  @Test("꺼진 기기의 삭제·초기화는 확인을 띄운다 (쓸 수 없는 기기는 삭제만)")
  func confirmations() async {
    let setup = await Self.loadedFixture()
    setup.model.deleteTapped(self.phone)
    #expect(setup.model.confirmation == self.confirmation(.delete, .phoneSample))
    setup.model.confirmationCancelled()
    setup.model.eraseTapped(self.phone)
    #expect(setup.model.confirmation == self.confirmation(.erase, .phoneSample))
    setup.model.confirmationCancelled()
    setup.model.eraseTapped(self.unsupported)
    #expect(setup.model.confirmation == nil)
    setup.model.deleteTapped(self.unsupported)
    #expect(setup.model.confirmation == self.confirmation(.delete, .unsupportedNameSample))
  }

  @Test("켜진 기기와 시트가 열려 있을 때는 확인을 띄우지 않는다")
  func confirmationBlocked() async {
    let setup = await Self.loadedFixture()
    setup.model.deleteTapped(self.tablet)
    setup.model.eraseTapped(self.tablet)
    #expect(setup.model.confirmation == nil)
    setup.model.createButtonTapped()
    setup.model.deleteTapped(self.phone)
    #expect(setup.model.confirmation == nil)
  }

  @Test("삭제: 확인을 닫고 지운 뒤 다시 읽는다")
  func deleteSucceeds() async {
    let setup = await Self.loadedFixture()
    let confirmation = self.confirmation(.delete, .phoneSample)
    setup.model.deleteTapped(self.phone)
    await setup.model.confirmationConfirmTapped(confirmation)
    #expect(setup.model.confirmation == nil)
    #expect(setup.fake.calls == [.fetchDevices, .delete(self.phone), .fetchDevices])
    #expect(Self.list(setup.model)?.device(id: self.phone) == nil)
    #expect(setup.model.notices.isEmpty)
  }

  @Test("삭제가 기기 폴더를 남기면 정보 알림을 띄운다")
  func deleteFolderKept() async {
    let folder = URL(filePath: "/Users/fake/elsewhere/", directoryHint: .isDirectory)
    let setup = await Self.loadedFixture { $0.setDeleteResult(.success(.folderKept(folder))) }
    let confirmation = self.confirmation(.delete, .phoneSample)
    await setup.model.confirmationConfirmTapped(confirmation)
    #expect(Self.notices(setup.model) == [.folderKept(AndroidDeviceLabel(.phoneSample), folder)])
  }

  @Test("초기화: 지운 뒤 다시 읽는다")
  func eraseSucceeds() async {
    let setup = await Self.loadedFixture()
    await setup.model.confirmationConfirmTapped(self.confirmation(.erase, .phoneSample))
    #expect(setup.fake.calls == [.fetchDevices, .erase(self.phone), .fetchDevices])
    #expect(setup.model.notices.isEmpty)
  }

  @Test(
    "삭제·초기화가 실패하면 원인과 함께 알리고 다시 읽는다",
    arguments: [
      AndroidEmulatorError.deviceRunning, .fileOperationFailed, .unsafeDeviceFolder(nil), .deviceNotFound,
    ]
  )
  func failures(error: AndroidEmulatorError) async {
    let setup = await Self.loadedFixture {
      $0.setDeleteResult(.failure(error))
      $0.setEraseError(error)
    }
    let label = AndroidDeviceLabel(.phoneSample)
    await setup.model.confirmationConfirmTapped(self.confirmation(.delete, .phoneSample))
    await setup.model.confirmationConfirmTapped(self.confirmation(.erase, .phoneSample))
    #expect(Self.notices(setup.model) == [.deleteFailed(label, error), .eraseFailed(label, error)])
    #expect(Self.fetchCount(setup.fake) == 3)
  }

  @Test("확인을 기다리는 동안 켜졌으면 실행하지 않고 켜져 있다고 알린다")
  func becameRunning() async {
    let setup = await Self.loadedFixture()
    setup.model.deleteTapped(self.phone)
    setup.fake.setInventory(AndroidDeviceInventory(
      devices: [AndroidVirtualDevice.phoneSample.with(state: .booted)],
      creationOptions: .sample
    ))
    await setup.model.refreshButtonTapped()
    await setup.model.confirmationConfirmTapped(self.confirmation(.delete, .phoneSample))
    #expect(Self.notices(setup.model) == [.deleteFailed(AndroidDeviceLabel(.phoneSample), .deviceRunning)])
    #expect(Self.count(.delete(self.phone), in: setup.fake) == 0)
  }

  @Test("확인을 기다리는 동안 목록에서 사라졌으면 찾지 못했다고 알린다")
  func disappeared() async {
    let setup = await Self.loadedFixture()
    setup.fake.setInventory(.emptySample)
    await setup.model.refreshButtonTapped()
    await setup.model.confirmationConfirmTapped(self.confirmation(.erase, .phoneSample))
    #expect(Self.notices(setup.model) == [.eraseFailed(AndroidDeviceLabel(.phoneSample), .deviceNotFound)])
    #expect(Self.count(.erase(self.phone), in: setup.fake) == 0)
  }

  @Test("지우는 동안 행은 삭제하는 중이고 다른 작업을 받지 않는다")
  func deletingBlocksTasks() async {
    let setup = await Self.loadedFixture { $0.suspendDeletes() }
    let delete = Self.start {
      await setup.model.confirmationConfirmTapped(self.confirmation(.delete, .phoneSample))
    }
    await Self.waitUntil { setup.fake.calls.contains(.delete(self.phone)) }
    #expect(setup.model.activity.task(on: self.phone) == .delete)
    await setup.model.bootTapped(self.phone)
    setup.model.eraseTapped(self.phone)
    #expect(Self.count(.boot(self.phone), in: setup.fake) == 0)
    #expect(setup.model.confirmation == nil)
    setup.fake.resumeDeletes()
    await delete.value()
    #expect(setup.model.activity.busyDeviceIDs.isEmpty)
  }
}
