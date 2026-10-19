import Core
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

@MainActor
struct LauncherFeatureTests: LauncherModelTesting {
  // MARK: - 목록 읽기

  @Test("onAppear 는 기기 목록을 읽어 화면 목록으로 바꾼다")
  func onAppearLoadsList() async {
    let fake = SimulatorClientFake(inventory: .sample)
    let model = LauncherModel(simulator: fake)
    #expect(model.listState == .loading)

    await model.onAppear()

    #expect(model.listState == .loaded(DeviceList(inventory: .sample)))
    #expect(model.isRefreshing == false)
    #expect(model.notices.isEmpty)
    #expect(fake.calls == [.fetchInventory])
  }

  @Test("첫 읽기가 실패하면 전체 오류가 되고, 새로 고침으로 회복한다")
  func firstLoadFailureRecoversByRefresh() async {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.setFetchError(.developerToolsUnavailable)
    let model = LauncherModel(simulator: fake)

    await model.onAppear()
    #expect(model.listState == .failed(.developerToolsUnavailable))
    #expect(model.notices.isEmpty)
    #expect(model.isRefreshing == false)

    fake.setFetchError(nil)
    await model.refreshButtonTapped()
    #expect(model.listState == .loaded(DeviceList(inventory: .sample)))
  }

  @Test("실패 상태에서 다시 읽는 동안은 로딩으로 보인다")
  func retryFromFailureShowsLoading() async {
    let (model, fake) = await Self.loadedModel { $0.setFetchError(.commandFailed) }

    fake.setFetchError(nil)
    fake.suspendFetches()
    let task = Task { await model.refreshButtonTapped() }
    await Self.waitUntil { fake.calls.count == 2 }
    #expect(model.listState == .loading)
    #expect(model.isRefreshing)

    fake.resumeFetches()
    await task.value
    #expect(model.listState == .loaded(DeviceList(inventory: .sample)))
  }

  @Test("읽는 중 들어온 onAppear·새로 고침은 겹쳐 읽지 않고, 끝난 뒤 한 번만 더 읽는다")
  func overlappingReloadsAreCoalesced() async {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.suspendFetches()
    let model = LauncherModel(simulator: fake)

    let first = Task { await model.onAppear() }
    await Self.waitUntil { fake.calls.contains(.fetchInventory) }
    #expect(model.listState == .loading)
    #expect(model.isRefreshing)

    let second = Task { await model.onAppear() }
    let third = Task { await model.refreshButtonTapped() }
    for _ in 0 ..< 20 {
      await Task.yield()
    }
    #expect(fake.calls == [.fetchInventory])

    fake.resumeFetches()
    await first.value
    await second.value
    await third.value
    #expect(fake.calls == [.fetchInventory, .fetchInventory])
    #expect(model.listState == .loaded(DeviceList(inventory: .sample)))
    #expect(model.isRefreshing == false)
  }

  @Test("목록이 있을 때 새로 고침이 실패하면 목록을 유지하고 알린다")
  func refreshFailureKeepsList() async {
    let (model, fake) = await Self.loadedModel()

    fake.setFetchError(.unexpectedOutput)
    await model.refreshButtonTapped()

    #expect(model.listState == .loaded(DeviceList(inventory: .sample)))
    #expect(model.notices.map(\.notice) == [.refreshFailed(.unexpectedOutput)])
    #expect(model.isRefreshing == false)
  }

  // MARK: - 켜기

  @Test("꺼진 기기를 켜면 켜기 → 앱 열기 → 다시 읽기 순서로 부르고 켜짐이 된다")
  func bootSuccess() async {
    let (model, fake) = await Self.loadedModel()

    await model.bootButtonTapped(SampleID.iPhoneOff)

    #expect(
      fake.calls == [.fetchInventory, .boot(SampleID.iPhoneOff), .openSimulatorApp, .fetchInventory]
    )
    #expect(Self.device(SampleID.iPhoneOff, in: model)?.state == .booted)
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.notices.isEmpty)
  }

  @Test("켜는 동안 같은 기기를 다시 눌러도 한 번만 켠다")
  func bootSameDeviceTwiceBootsOnce() async {
    let (model, fake) = await Self.loadedModel()

    fake.suspendBoots()
    let task = Task { await model.bootButtonTapped(SampleID.iPhoneOff) }
    await Self.waitUntil { fake.calls.contains(.boot(SampleID.iPhoneOff)) }
    #expect(model.busyDeviceIDs == [SampleID.iPhoneOff])

    let second = Self.start { await model.bootButtonTapped(SampleID.iPhoneOff) }
    await Self.waitUntil { second.isFinished || Self.bootCount(SampleID.iPhoneOff, in: fake) > 1 }
    #expect(Self.bootCount(SampleID.iPhoneOff, in: fake) == 1)

    fake.resumeBoots()
    await task.value
    await second.value()
    #expect(fake.calls.filter { $0 == .boot(SampleID.iPhoneOff) }.count == 1)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("두 기기를 함께 켜면 둘 다 진행 중이 되고, 둘 다 켜진다")
  func bootTwoDevicesConcurrently() async {
    let (model, fake) = await Self.loadedModel()

    fake.suspendBoots()
    let phone = Task { await model.bootButtonTapped(SampleID.iPhoneOff) }
    let pad = Task { await model.bootButtonTapped(SampleID.iPadOff) }
    await Self.waitUntil {
      fake.calls.contains(.boot(SampleID.iPhoneOff)) && fake.calls.contains(.boot(SampleID.iPadOff))
    }
    #expect(model.busyDeviceIDs == [SampleID.iPhoneOff, SampleID.iPadOff])

    fake.resumeBoots()
    await phone.value
    await pad.value
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(fake.calls.filter { $0 == .openSimulatorApp }.count == 2)
    #expect(Self.device(SampleID.iPhoneOff, in: model)?.state == .booted)
    #expect(Self.device(SampleID.iPadOff, in: model)?.state == .booted)
  }

  @Test("켜기가 실패하면 알리고 목록을 다시 읽으며, 진행 중을 푼다")
  func bootFailureNotifiesAndReloads() async {
    let (model, fake) = await Self.loadedModel { $0.setBootError(.commandFailed) }

    await model.bootButtonTapped(SampleID.iPhoneOff)

    #expect(model.notices.map(\.notice) == [.bootFailed(Self.label(SampleID.iPhoneOff), .commandFailed)])
    #expect(fake.calls == [.fetchInventory, .boot(SampleID.iPhoneOff), .fetchInventory])
    #expect(Self.device(SampleID.iPhoneOff, in: model)?.state == .shutdown)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("켜기 실패 뒤 다시 읽기도 실패하면 두 알림을 차례로 쌓고 목록을 유지한다")
  func bootFailureThenRefreshFailureQueuesBoth() async {
    let (model, fake) = await Self.loadedModel()

    fake.setBootError(.deviceNotFound)
    fake.setFetchError(.commandFailed)
    await model.bootButtonTapped(SampleID.iPhoneOff)

    #expect(
      model.notices.map(\.notice) == [
        .bootFailed(Self.label(SampleID.iPhoneOff), .deviceNotFound), .refreshFailed(.commandFailed),
      ]
    )
    #expect(model.listState == .loaded(DeviceList(inventory: .sample)))
    #expect(fake.calls == [.fetchInventory, .boot(SampleID.iPhoneOff), .fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("켜졌지만 앱을 열지 못하면 알리고, 기기는 켜짐으로 보인다")
  func openAppFailureAfterBoot() async {
    let (model, fake) = await Self.loadedModel { $0.setOpenAppError(.simulatorAppNotFound) }

    await model.bootButtonTapped(SampleID.iPhoneOff)

    #expect(
      model.notices.map(\.notice) == [.openAppFailed(Self.label(SampleID.iPhoneOff), .simulatorAppNotFound)]
    )
    #expect(Self.device(SampleID.iPhoneOff, in: model)?.state == .booted)
    #expect(fake.calls.last == .fetchInventory)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("켜는 동안 새로 고침해도 켜기는 이어지고, 끝나면 켜짐이 된다")
  func refreshDuringBoot() async {
    let (model, fake) = await Self.loadedModel()

    fake.suspendBoots()
    let task = Task { await model.bootButtonTapped(SampleID.iPhoneOff) }
    await Self.waitUntil { fake.calls.contains(.boot(SampleID.iPhoneOff)) }

    await model.refreshButtonTapped()
    #expect(Self.device(SampleID.iPhoneOff, in: model)?.state == .shutdown)
    #expect(model.busyDeviceIDs == [SampleID.iPhoneOff])

    fake.resumeBoots()
    await task.value
    #expect(Self.device(SampleID.iPhoneOff, in: model)?.state == .booted)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  // MARK: - 끄기

  @Test("켜진 기기를 끄면 끄기 → 다시 읽기 순서로 부르고 꺼짐이 된다")
  func shutdownSuccess() async {
    let (model, fake) = await Self.loadedModel()

    await model.shutdownButtonTapped(SampleID.iPhoneOn)

    #expect(fake.calls == [.fetchInventory, .shutdown(SampleID.iPhoneOn), .fetchInventory])
    #expect(Self.device(SampleID.iPhoneOn, in: model)?.state == .shutdown)
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.notices.isEmpty)
  }

  @Test("끄기가 실패하면 알리고 목록을 다시 읽으며, 진행 중을 푼다")
  func shutdownFailureNotifiesAndReloads() async {
    let (model, fake) = await Self.loadedModel { $0.setShutdownError(.commandFailed) }

    await model.shutdownButtonTapped(SampleID.iPhoneOn)

    #expect(model.notices.map(\.notice) == [.shutdownFailed(Self.label(SampleID.iPhoneOn), .commandFailed)])
    #expect(fake.calls == [.fetchInventory, .shutdown(SampleID.iPhoneOn), .fetchInventory])
    #expect(Self.device(SampleID.iPhoneOn, in: model)?.state == .booted)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  // MARK: - 조작할 수 없는 기기

  @Test("쓸 수 없는·켜진·목록에 없는 기기 켜기와 꺼진 기기 끄기는 아무것도 부르지 않는다")
  func invalidActionsCallNothing() async {
    let (model, fake) = await Self.loadedModel()

    await model.bootButtonTapped(SampleID.unavailableIPhone)
    await model.bootButtonTapped(SampleID.iPhoneOn)
    await model.bootButtonTapped(SampleID.watch)
    await model.shutdownButtonTapped(SampleID.iPhoneOff)

    #expect(fake.calls == [.fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.notices.isEmpty)
  }

  @Test("목록을 읽기 전에는 켜기·끄기가 아무것도 부르지 않는다")
  func actionsBeforeLoadCallNothing() async {
    let fake = SimulatorClientFake(inventory: .sample)
    let model = LauncherModel(simulator: fake)

    await model.bootButtonTapped(SampleID.iPhoneOff)
    await model.shutdownButtonTapped(SampleID.iPhoneOn)

    #expect(fake.calls.isEmpty)
  }
}

// MARK: - 알림

extension LauncherFeatureTests {
  @Test("켜기와 끄기가 겹쳐 둘 다 실패하면 실패한 순서대로 쌓인다")
  func overlappingFailuresQueueInOrder() async {
    let (model, fake) = await Self.loadedModel { fake in
      fake.setBootError(.commandFailed)
      fake.setShutdownError(.deviceNotFound)
    }

    fake.suspendBoots()
    let task = Task { await model.bootButtonTapped(SampleID.iPhoneOff) }
    await Self.waitUntil { fake.calls.contains(.boot(SampleID.iPhoneOff)) }
    await model.shutdownButtonTapped(SampleID.iPhoneOn)
    fake.resumeBoots()
    await task.value

    #expect(
      model.notices.map(\.notice) == [
        .shutdownFailed(Self.label(SampleID.iPhoneOn), .deviceNotFound),
        .bootFailed(Self.label(SampleID.iPhoneOff), .commandFailed),
      ]
    )
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("알림을 닫으면 그 알림만 빠져 다음 알림이 첫 알림이 되고, 이미 닫은 알림을 다시 닫아도 다른 알림은 남는다")
  func dismissingRemovesOnlyThatNotice() async throws {
    let (model, fake) = await Self.loadedModel()
    fake.setBootError(.commandFailed)
    fake.setFetchError(.unexpectedOutput)
    await model.bootButtonTapped(SampleID.iPhoneOff)
    try #require(model.notices.count == 2)
    let first = model.notices[0]
    let second = model.notices[1]

    model.noticeDismissed(first.id)
    model.noticeDismissed(first.id)
    #expect(model.notices == [second])

    model.noticeDismissed(second.id)
    model.noticeDismissed(second.id)
    #expect(model.notices.isEmpty)
  }

  @Test("같은 원인의 새로 고침 실패는 줄에 한 번만 쌓이고, 닫은 뒤 다시 나면 새 id 로 쌓인다")
  func sameRefreshFailureQueuedOnceUntilDismissed() async throws {
    let (model, fake) = await Self.loadedModel()
    fake.setFetchError(.commandFailed)
    await model.refreshButtonTapped()
    await model.refreshButtonTapped()
    #expect(model.notices.map(\.notice) == [.refreshFailed(.commandFailed)])
    let first = try #require(model.notices.first)

    model.noticeDismissed(first.id)
    await model.refreshButtonTapped()

    #expect(model.notices.map(\.notice) == [.refreshFailed(.commandFailed)])
    #expect(model.notices.first?.id != first.id)
  }

  @Test("두 기기 켜기가 같은 원인으로 함께 실패하면 기기마다 쌓인다")
  func sameBootFailureOnTwoDevicesQueuesEach() async {
    let (model, fake) = await Self.loadedModel { $0.setBootError(.commandFailed) }

    fake.suspendBoots()
    let phone = Task { await model.bootButtonTapped(SampleID.iPhoneOff) }
    let pad = Task { await model.bootButtonTapped(SampleID.iPadOff) }
    await Self.waitUntil {
      fake.calls.contains(.boot(SampleID.iPhoneOff)) && fake.calls.contains(.boot(SampleID.iPadOff))
    }
    fake.resumeBoots()
    await phone.value
    await pad.value

    #expect(model.notices.count == 2)
    #expect(
      Set(model.notices.map(\.notice)) == [
        .bootFailed(Self.label(SampleID.iPhoneOff), .commandFailed),
        .bootFailed(Self.label(SampleID.iPadOff), .commandFailed),
      ]
    )
  }

  @Test("실패 뒤 목록에서 사라진 기기도 누른 시점의 이름으로 알린다")
  func noticeKeepsNameOfRemovedDevice() async {
    let (model, fake) = await Self.loadedModel()

    fake.suspendBoots()
    let task = Task { await model.bootButtonTapped(SampleID.iPhoneOff) }
    await Self.waitUntil { fake.calls.contains(.boot(SampleID.iPhoneOff)) }
    let sample = DeviceInventory.sample
    fake.setInventory(
      DeviceInventory(
        devices: sample.devices.filter { $0.id != SampleID.iPhoneOff },
        runtimes: sample.runtimes,
        deviceTypes: sample.deviceTypes
      )
    )
    fake.setBootError(.deviceNotFound)
    fake.resumeBoots()
    await task.value

    #expect(Self.device(SampleID.iPhoneOff, in: model) == nil)
    #expect(model.notices.map(\.notice) == [.bootFailed(Self.label(SampleID.iPhoneOff), .deviceNotFound)])
  }
}
