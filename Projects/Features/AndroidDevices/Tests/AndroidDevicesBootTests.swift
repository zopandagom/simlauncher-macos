import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 켜기·끄기 (켜는 중 끄기 막기 D7 포함).
@MainActor
struct AndroidDevicesBootTests: AndroidDevicesTesting {
  private let phone = AndroidVirtualDevice.phoneSample.id
  private let tablet = AndroidVirtualDevice.bootedTabletSample.id

  @Test("켜기: 켠 뒤 다시 읽어 켜짐으로 보이고 작업 기록을 지운다")
  func bootSucceeds() async {
    let setup = await Self.loadedFixture()
    await setup.model.bootTapped(self.phone)
    #expect(setup.fake.calls == [.fetchDevices, .boot(self.phone), .fetchDevices])
    #expect(Self.list(setup.model)?.device(id: self.phone)?.state == .booted)
    #expect(setup.model.activity.busyDeviceIDs.isEmpty)
    #expect(setup.model.notices.isEmpty)
  }

  @Test("켜는 동안 행은 켜는 중이고, 앱이 켜는 중인 기기는 끄기·다시 켜기·삭제를 막는다 (D7)")
  func bootingBlocksOtherTasks() async {
    let setup = await Self.loadedFixture { $0.suspendBoots() }
    let boot = Self.start { await setup.model.bootTapped(self.phone) }
    await Self.waitUntil { setup.fake.calls.contains(.boot(self.phone)) }
    #expect(setup.model.activity.task(on: self.phone) == .boot)
    // 앱 밖 사실은 켜는 중이어도 앱 작업이 막는다.
    setup.fake.setInventory(AndroidDeviceInventory(
      devices: [AndroidVirtualDevice.phoneSample.with(state: .booting)],
      creationOptions: .sample
    ))
    await setup.model.refreshButtonTapped()
    await setup.model.shutdownTapped(self.phone)
    await setup.model.bootTapped(self.phone)
    setup.model.deleteTapped(self.phone)
    #expect(Self.count(.shutdown(self.phone), in: setup.fake) == 0)
    #expect(Self.count(.boot(self.phone), in: setup.fake) == 1)
    #expect(setup.model.confirmation == nil)
    setup.fake.resumeBoots()
    await boot.value()
    #expect(setup.model.activity.task(on: self.phone) == nil)
  }

  @Test(
    "켤 수 없는 기기(켜짐·쓸 수 없음·목록에 없음)는 켜지 않는다",
    arguments: [
      AndroidVirtualDevice.bootedTabletSample.id, AndroidVirtualDevice.unsupportedNameSample.id,
      AndroidVirtualDevice.missingImageSample.id, AndroidVirtualDevice.ID("Nope"),
    ]
  )
  func bootIgnored(id: AndroidVirtualDevice.ID) async {
    let setup = await Self.loadedFixture()
    await setup.model.bootTapped(id)
    #expect(setup.fake.calls == [.fetchDevices])
  }

  @Test(
    "켜기가 실패하면 원인과 함께 알리고 다시 읽는다",
    arguments: [
      AndroidEmulatorError.emulatorExited(1), .emulatorExited(nil), .bootTimedOut, .emulatorLaunchFailed,
      .sdkUnavailable, .deviceUnavailable(.configUnreadable), .deviceNotFound,
    ]
  )
  func bootFailure(error: AndroidEmulatorError) async {
    let setup = await Self.loadedFixture { $0.setBootError(error) }
    await setup.model.bootTapped(self.phone)
    #expect(Self.notices(setup.model) == [.bootFailed(AndroidDeviceLabel(.phoneSample), error)])
    #expect(Self.fetchCount(setup.fake) == 2)
    #expect(setup.model.activity.busyDeviceIDs.isEmpty)
  }

  @Test("켜기가 취소되면 알리지 않는다")
  func bootCancelledIsSilent() async {
    let setup = await Self.loadedFixture { $0.setBootError(.cancelled) }
    await setup.model.bootTapped(self.phone)
    #expect(setup.model.notices.isEmpty)
    #expect(Self.fetchCount(setup.fake) == 2)
  }

  @Test("끄기: 켜진 기기를 끄고 다시 읽는다")
  func shutdownSucceeds() async {
    let setup = await Self.loadedFixture()
    await setup.model.shutdownTapped(self.tablet)
    #expect(setup.fake.calls == [.fetchDevices, .shutdown(self.tablet), .fetchDevices])
    #expect(Self.list(setup.model)?.device(id: self.tablet)?.state == .shutdown)
  }

  @Test("앱 밖에서 켜는 중인 기기와 쓸 수 없지만 실행 중인 기기는 끌 수 있다")
  func shutdownOutsideBootingAndUnavailable() async {
    let unavailableRunning = AndroidVirtualDevice.missingImageSample.with(state: .booted)
    let setup = await Self.loadedFixture(AndroidDeviceInventory(
      devices: [.bootingSample, unavailableRunning],
      creationOptions: .sample
    ))
    await setup.model.shutdownTapped(AndroidVirtualDevice.bootingSample.id)
    await setup.model.shutdownTapped(unavailableRunning.id)
    #expect(Self.count(.shutdown(AndroidVirtualDevice.bootingSample.id), in: setup.fake) == 1)
    #expect(Self.count(.shutdown(unavailableRunning.id), in: setup.fake) == 1)
  }

  @Test("꺼진 기기는 끄지 않는다")
  func shutdownIgnoredWhenOff() async {
    let setup = await Self.loadedFixture()
    await setup.model.shutdownTapped(self.phone)
    #expect(setup.fake.calls == [.fetchDevices])
  }

  @Test(
    "끄기가 실패하면 원인과 함께 알리고 다시 읽는다",
    arguments: [AndroidEmulatorError.adbUnavailable, .shutdownTimedOut, .sdkUnavailable]
  )
  func shutdownFailure(error: AndroidEmulatorError) async {
    let setup = await Self.loadedFixture { $0.setShutdownError(error) }
    await setup.model.shutdownTapped(self.tablet)
    #expect(Self.notices(setup.model) == [.shutdownFailed(AndroidDeviceLabel(.bootedTabletSample), error)])
    #expect(Self.fetchCount(setup.fake) == 2)
  }

  @Test("끄는 동안 행은 끄는 중이고 다시 끄지 않는다")
  func shuttingDownBlocksRepeat() async {
    let setup = await Self.loadedFixture { $0.suspendShutdowns() }
    let shutdown = Self.start { await setup.model.shutdownTapped(self.tablet) }
    await Self.waitUntil { setup.fake.calls.contains(.shutdown(self.tablet)) }
    #expect(setup.model.activity.task(on: self.tablet) == .shutdown)
    await setup.model.shutdownTapped(self.tablet)
    #expect(Self.count(.shutdown(self.tablet), in: setup.fake) == 1)
    setup.fake.resumeShutdowns()
    await shutdown.value()
  }
}

/// 툴바 "선택한 기기 켜기".
@MainActor
struct AndroidDevicesBatchBootTests: AndroidDevicesTesting {
  private static let inventory = AndroidDeviceInventory(
    devices: [.phoneSample, .secondPhoneSample, .bootedTabletSample, .unsupportedNameSample],
    creationOptions: .sample
  )
  private let phone = AndroidVirtualDevice.phoneSample.id
  private let second = AndroidVirtualDevice.secondPhoneSample.id

  @Test("고른 기기 중 켤 수 있는 기기만 함께 켜고, 모두 켜지면 알림이 없다")
  func bootsOnlyBootable() async {
    let setup = await Self.loadedFixture(Self.inventory)
    setup.model.selectionChanged(Set(Self.inventory.devices.map(\.id)))
    #expect(setup.model.canBootSelection)
    await setup.model.bootSelectedTapped()
    let boots = setup.fake.calls.filter {
      if case .boot = $0 {
        true
      } else {
        false
      }
    }
    #expect(Set(boots) == [.boot(self.phone), .boot(self.second)])
    #expect(setup.model.notices.isEmpty)
    #expect(setup.model.activity.busyDeviceIDs.isEmpty)
  }

  @Test("실패가 있으면 시작한 기기의 결과를 알림 하나로 모은다 (목록 순서)")
  func partialFailureReport() async {
    let setup = await Self.loadedFixture(Self.inventory) { $0.setBootError(.bootTimedOut, for: self.second) }
    setup.model.selectionChanged([self.phone, self.second, AndroidVirtualDevice.bootedTabletSample.id])
    await setup.model.bootSelectedTapped()
    let report = AndroidBatchBootReport(entries: [
      .init(device: AndroidDeviceLabel(.secondPhoneSample), error: .bootTimedOut),
      .init(device: AndroidDeviceLabel(.phoneSample), error: nil),
    ])
    #expect(Self.notices(setup.model) == [.batchBootFinished(report)])
    #expect(report.successCount == 1)
  }

  @Test("모두 실패하면 결과 알림 하나")
  func allFailReport() async {
    let setup = await Self.loadedFixture(Self.inventory) { $0.setBootError(.emulatorExited(1)) }
    setup.model.selectionChanged([self.phone, self.second])
    await setup.model.bootSelectedTapped()
    guard case let .batchBootFinished(report) = Self.notices(setup.model).first else {
      Issue.record("결과 알림이 없다")
      return
    }
    #expect(report.successCount == 0)
    #expect(report.entries.count == 2)
  }

  @Test("켤 수 있는 기기가 한 대면 행 켜기와 같은 알림이다")
  func singleIsLikeRow() async {
    let setup = await Self.loadedFixture(Self.inventory) { $0.setBootError(.bootTimedOut) }
    setup.model.selectionChanged([self.phone, AndroidVirtualDevice.bootedTabletSample.id])
    await setup.model.bootSelectedTapped()
    #expect(Self.notices(setup.model) == [.bootFailed(AndroidDeviceLabel(.phoneSample), .bootTimedOut)])
    #expect(setup.model.activity.busyDeviceIDs.isEmpty)
  }

  @Test("켤 수 있는 기기가 없으면 아무것도 하지 않는다")
  func nothingToBoot() async {
    let setup = await Self.loadedFixture(Self.inventory)
    setup.model.selectionChanged([
      AndroidVirtualDevice.bootedTabletSample.id,
      AndroidVirtualDevice.unsupportedNameSample.id,
    ])
    #expect(!setup.model.canBootSelection)
    await setup.model.bootSelectedTapped()
    #expect(setup.fake.calls == [.fetchDevices])
  }

  @Test("먼저 끝난 기기는 다시 읽고 바로 풀며, 다른 기기는 계속 켜는 중이다")
  func firstFinishedReleased() async {
    let setup = await Self.loadedFixture(Self.inventory) { $0.suspendBoot(of: self.second) }
    setup.model.selectionChanged([self.phone, self.second])
    let batch = Self.start { await setup.model.bootSelectedTapped() }
    // 작업 기록은 묶음이 시작되기 전에도 비어 있으므로, 두 기기 켜기가 불린 뒤 먼저 끝난 기기가 풀리기를 기다린다.
    await Self.waitUntil {
      setup.fake.calls.contains(.boot(self.second)) && setup.model.activity.task(on: self.phone) == nil
    }
    #expect(setup.model.activity.task(on: self.second) == .boot)
    #expect(Self.list(setup.model)?.device(id: self.phone)?.state == .booted)
    // 풀린 기기는 묶음이 끝나기 전에 다시 작업할 수 있고, 묶음의 끝이 그 기록을 지우지 않는다.
    setup.fake.suspendShutdowns()
    let shutdown = Self.start { await setup.model.shutdownTapped(self.phone) }
    await Self.waitUntil { setup.fake.calls.contains(.shutdown(self.phone)) }
    setup.fake.resumeBoot(of: self.second)
    await batch.value()
    #expect(setup.model.activity.task(on: self.phone) == .shutdown)
    setup.fake.resumeShutdowns()
    await shutdown.value()
  }
}
