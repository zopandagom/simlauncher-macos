import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 목록 읽기(onAppear·새로 고침·실패·모으기)·선택·Android 도구 버튼·알림 닫기.
@MainActor
struct AndroidDevicesListTests: AndroidDevicesTesting {
  @Test("처음에는 읽는 중이고 만들 수 없다")
  func initialState() {
    let setup = Self.fixture()
    #expect(setup.model.listState == .loading)
    #expect(!setup.model.canCreateDevice)
    #expect(setup.fake.calls.isEmpty)
  }

  @Test("화면이 보이면 목록을 읽어 Core 목록 순서로 보이고 선택지를 기억한다")
  func onAppearLoads() async {
    let setup = await Self.loadedFixture()
    // 순서 규칙(localizedStandardCompare)은 Core AndroidDeviceListTests 가 고정한다. 한글과 라틴 문자가 섞인
    // 샘플의 순서는 실행 환경 로케일에 따라 다르므로 같은 Core 값과 비교한다.
    #expect(Self.list(setup.model) == AndroidDeviceList(devices: AndroidDeviceInventory.sample.devices))
    #expect(setup.model.creationOptions == .sample)
    #expect(setup.model.canCreateDevice)
    #expect(!setup.model.isRefreshing)
    #expect(Self.fetchCount(setup.fake) == 1)
  }

  @Test("목록을 한 번도 읽지 못하면 실패 화면이고, 새로 고침이 다시 읽는다")
  func firstLoadFailure() async {
    let setup = await Self.loadedFixture { $0.setFetchError(.avdFolderUnavailable) }
    #expect(setup.model.listState == .failed(.avdFolderUnavailable))
    #expect(setup.model.notices.isEmpty)
    setup.fake.setFetchError(nil)
    await setup.model.refreshButtonTapped()
    #expect(Self.list(setup.model) != nil)
  }

  @Test("목록이 있을 때 새로 고침이 실패하면 목록을 두고 알림을 띄운다 (같은 원인은 하나만)")
  func refreshFailureKeepsList() async {
    let setup = await Self.loadedFixture()
    setup.fake.setFetchError(.adbUnavailable)
    await setup.model.refreshButtonTapped()
    await setup.model.refreshButtonTapped()
    #expect(Self.list(setup.model) != nil)
    #expect(Self.notices(setup.model) == [.refreshFailed(.adbUnavailable)])
  }

  @Test("Android 도구를 찾지 못하면 목록이 있어도 실패 화면으로 바꾸고 선택을 지운다")
  func sdkUnavailableReplacesList() async {
    let setup = await Self.loadedFixture()
    setup.model.selectionChanged([AndroidVirtualDevice.phoneSample.id])
    setup.fake.setFetchError(.sdkUnavailable)
    await setup.model.refreshButtonTapped()
    #expect(setup.model.listState == .failed(.sdkUnavailable))
    #expect(setup.model.selection.isEmpty)
    #expect(setup.model.notices.isEmpty)
  }

  @Test("읽는 중에 온 요청은 모아서 지금 읽기가 끝난 뒤 한 번 더 읽는다")
  func reloadsCoalesce() async {
    let setup = await Self.loadedFixture()
    setup.fake.suspendFetches()
    let first = Self.start { await setup.model.refreshButtonTapped() }
    await Self.waitUntil { Self.fetchCount(setup.fake) == 2 }
    #expect(setup.model.isRefreshing)
    let second = Self.start { await setup.model.refreshButtonTapped() }
    let third = Self.start { await setup.model.sdkLocationChanged() }
    await Self.settle()
    #expect(Self.fetchCount(setup.fake) == 2)
    setup.fake.setInventory(.emptySample)
    setup.fake.resumeFetches()
    await first.value()
    await second.value()
    await third.value()
    #expect(Self.fetchCount(setup.fake) == 3)
    #expect(Self.list(setup.model)?.emptyReason == .noDevices)
    #expect(!setup.model.isRefreshing)
  }

  @Test("선택은 다시 읽은 목록에 있는 기기만 남는다")
  func selectionFollowsList() async {
    let setup = await Self.loadedFixture()
    let phone = AndroidVirtualDevice.phoneSample.id
    let tablet = AndroidVirtualDevice.bootedTabletSample.id
    setup.model.selectionChanged([phone, tablet])
    #expect(setup.model.selection == [phone, tablet])
    // 고른 기기는 목록 순서를 따른다 (그 순서는 로케일에 따라 다르므로 목록에서 만든다).
    let listOrder = Self.list(setup.model)?.devices.map(\.id).filter { [phone, tablet].contains($0) }
    #expect(setup.model.selectedDevices.map(\.id) == listOrder)
    #expect(listOrder?.count == 2)
    setup.fake.setInventory(AndroidDeviceInventory(devices: [.phoneSample], creationOptions: .sample))
    await setup.model.refreshButtonTapped()
    #expect(setup.model.selection == [phone])
  }

  @Test("SDK 위치가 바뀌면 화면이 보일 때만 다시 읽는다")
  func sdkLocationChanged() async {
    let hidden = Self.fixture()
    await hidden.model.sdkLocationChanged()
    #expect(hidden.fake.calls.isEmpty)
    let setup = await Self.loadedFixture()
    await setup.model.sdkLocationChanged()
    #expect(Self.fetchCount(setup.fake) == 2)
    setup.model.viewDisappeared()
    await setup.model.sdkLocationChanged()
    #expect(Self.fetchCount(setup.fake) == 2)
  }

  @Test("Android 도구 버튼은 App 이 주입한 클로저를 부른다")
  func setupButton() async {
    let setup = await Self.loadedFixture()
    setup.model.setupButtonTapped()
    #expect(setup.setupRequests.value == 1)
  }

  @Test("알림 닫기는 그 id 만 지운다 (두 번 불려도 다음 알림은 남는다)")
  func noticeDismissed() async {
    let setup = await Self.loadedFixture { $0.setShutdownError(.adbUnavailable) }
    let tablet = AndroidVirtualDevice.bootedTabletSample.id
    await setup.model.shutdownTapped(tablet)
    await setup.model.shutdownTapped(tablet)
    #expect(setup.model.notices.count == 2)
    let first = setup.model.notices[0].id
    setup.model.noticeDismissed(first)
    setup.model.noticeDismissed(first)
    #expect(setup.model.notices.count == 1)
    #expect(setup.model.notices[0].id != first)
  }

  @Test("기기가 없으면 빈 화면이고, 만들 이미지가 없으면 만들 수 없다")
  func emptyAndNoImage() async {
    let setup = await Self.loadedFixture(AndroidDeviceInventory(devices: [], creationOptions: .emptySample))
    #expect(Self.list(setup.model)?.emptyReason == .noDevices)
    #expect(setup.model.isCreationUnavailable)
    #expect(!setup.model.canCreateDevice)
  }
}

/// 자동 다시 읽기: 앱 작업 없이 켜는 중인 기기(2초 간격)와 앱 활성화(곧바로 + 3초 뒤).
@MainActor
struct AndroidDevicesAutoRefreshTests: AndroidDevicesTesting {
  private static let bootingInventory = AndroidDeviceInventory(
    devices: [.phoneSample, .bootingSample],
    creationOptions: .sample
  )

  @Test("앱 작업 없이 켜는 중인 기기가 있으면 2초 뒤 다시 읽고, 없어지면 멈춘다")
  func bootingDeviceRefreshesEveryTwoSeconds() async {
    let setup = await Self.loadedFixture(Self.bootingInventory)
    await Self.waitUntil { setup.sleeper.pendingCount == 1 }
    #expect(setup.sleeper.requested == [.seconds(2)])
    setup.sleeper.resumeAll()
    await Self.waitUntil { Self.fetchCount(setup.fake) == 2 }
    // 아직 켜는 중이라 다음 2초를 기다린다.
    await Self.waitUntil { setup.sleeper.pendingCount == 1 }
    setup.fake.setInventory(AndroidDeviceInventory(
      devices: [.phoneSample, AndroidVirtualDevice.bootingSample.with(state: .booted)],
      creationOptions: .sample
    ))
    setup.sleeper.resumeAll()
    await Self.waitUntil { Self.fetchCount(setup.fake) == 3 }
    await Self.settle()
    #expect(setup.sleeper.pendingCount == 0)
    #expect(setup.sleeper.requested.count == 2)
  }

  @Test("켜는 중인 기기가 없으면 자동으로 다시 읽지 않는다")
  func noBootingDeviceNoTimer() async {
    let setup = await Self.loadedFixture()
    await Self.settle()
    #expect(setup.sleeper.requested.isEmpty)
  }

  @Test("화면이 사라지면 자동 다시 읽기를 멈추고, 다시 보이면 다시 시작한다")
  func viewDisappearedStops() async {
    let setup = await Self.loadedFixture(Self.bootingInventory)
    await Self.waitUntil { setup.sleeper.pendingCount == 1 }
    setup.model.viewDisappeared()
    setup.sleeper.resumeAll()
    await Self.settle()
    #expect(Self.fetchCount(setup.fake) == 1)
    await setup.model.onAppear()
    #expect(Self.fetchCount(setup.fake) == 2)
    await Self.waitUntil { setup.sleeper.pendingCount == 1 }
    #expect(setup.sleeper.requested.count == 2)
  }

  @Test("앱이 켜는 중인 기기는 자동 다시 읽기에서 세지 않는다 (작업이 끝날 때 다시 읽는다)")
  func appBootingDeviceNotCounted() async {
    let setup = await Self.loadedFixture { $0.suspendBoots() }
    let boot = Self.start { await setup.model.bootTapped(AndroidVirtualDevice.phoneSample.id) }
    await Self.waitUntil { setup.fake.calls.contains(.boot(AndroidVirtualDevice.phoneSample.id)) }
    // Fake 가 켜는 중으로 보이게 바꾸고 다른 이유로 다시 읽는다.
    setup.fake.setInventory(AndroidDeviceInventory(
      devices: [AndroidVirtualDevice.phoneSample.with(state: .booting)],
      creationOptions: .sample
    ))
    await setup.model.refreshButtonTapped()
    await Self.settle()
    #expect(setup.sleeper.requested.isEmpty)
    setup.fake.resumeBoots()
    await boot.value()
  }

  @Test("켜기가 실패해 앱 밖 켜는 중으로 남으면 작업이 끝난 뒤 자동 다시 읽기를 시작한다 (시간 초과)")
  func bootTimeoutStartsAutoRefresh() async {
    let setup = await Self.loadedFixture { $0.setBootError(.bootTimedOut) }
    setup.fake.setInventory(AndroidDeviceInventory(
      devices: [AndroidVirtualDevice.phoneSample.with(state: .booting)],
      creationOptions: .sample
    ))
    await setup.model.bootTapped(AndroidVirtualDevice.phoneSample.id)
    #expect(Self.notices(setup.model) == [.bootFailed(AndroidDeviceLabel(.phoneSample), .bootTimedOut)])
    await Self.waitUntil { setup.sleeper.pendingCount == 1 }
    #expect(setup.sleeper.requested == [.seconds(2)])
  }

  @Test("앱 활성화는 곧바로 다시 읽고 3초 뒤 한 번 더 읽는다")
  func activationRefreshesTwice() async {
    let setup = await Self.loadedFixture()
    await setup.model.appBecameActive()
    #expect(Self.fetchCount(setup.fake) == 2)
    await Self.waitUntil { setup.sleeper.pendingCount == 1 }
    #expect(setup.sleeper.requested == [.seconds(3)])
    setup.sleeper.resumeAll()
    await Self.waitUntil { Self.fetchCount(setup.fake) == 3 }
  }

  @Test("앱 활성화 3초 뒤 읽기는 화면이 사라지면 취소된다")
  func activationFollowUpCancelledOnDisappear() async {
    let setup = await Self.loadedFixture()
    await setup.model.appBecameActive()
    await Self.waitUntil { setup.sleeper.pendingCount == 1 }
    setup.model.viewDisappeared()
    setup.sleeper.resumeAll()
    await Self.settle()
    #expect(Self.fetchCount(setup.fake) == 2)
  }

  @Test("만들기 시트가 열려 있거나 화면이 보이지 않으면 앱 활성화를 무시한다")
  func activationIgnoredWithSheetOrHidden() async {
    let setup = await Self.loadedFixture()
    setup.model.createButtonTapped()
    await setup.model.appBecameActive()
    #expect(Self.fetchCount(setup.fake) == 1)
    let hidden = Self.fixture()
    await hidden.model.appBecameActive()
    #expect(hidden.fake.calls.isEmpty)
  }
}
