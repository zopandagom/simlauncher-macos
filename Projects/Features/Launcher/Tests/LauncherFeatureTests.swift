import Core
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

@MainActor
struct LauncherFeatureTests {
  // MARK: - 목록 읽기

  @Test("onAppear 는 기기 목록을 읽어 화면 목록으로 바꾼다")
  func onAppearLoadsList() async {
    let fake = SimulatorClientFake(inventory: .sample)
    let model = LauncherModel(simulator: fake)
    #expect(model.listState == .loading)

    await model.onAppear()

    #expect(model.listState == .loaded(DeviceList(inventory: .sample)))
    #expect(model.isRefreshing == false)
    #expect(model.notice == nil)
    #expect(fake.calls == [.fetchInventory])
  }

  @Test("첫 읽기가 실패하면 전체 오류가 되고, 새로 고침으로 회복한다")
  func firstLoadFailureRecoversByRefresh() async {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.setFetchError(.developerToolsUnavailable)
    let model = LauncherModel(simulator: fake)

    await model.onAppear()
    #expect(model.listState == .failed(.developerToolsUnavailable))
    #expect(model.notice == nil)
    #expect(model.isRefreshing == false)

    fake.setFetchError(nil)
    await model.refreshButtonTapped()
    #expect(model.listState == .loaded(DeviceList(inventory: .sample)))
  }

  @Test("실패 상태에서 다시 읽는 동안은 로딩으로 보인다")
  func retryFromFailureShowsLoading() async {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.setFetchError(.commandFailed)
    let model = LauncherModel(simulator: fake)
    await model.onAppear()

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
    let fake = SimulatorClientFake(inventory: .sample)
    let model = LauncherModel(simulator: fake)
    await model.onAppear()

    fake.setFetchError(.unexpectedOutput)
    await model.refreshButtonTapped()

    #expect(model.listState == .loaded(DeviceList(inventory: .sample)))
    #expect(model.notice == .refreshFailed(.unexpectedOutput))
    #expect(model.isRefreshing == false)
  }

  // MARK: - 켜기

  @Test("꺼진 기기를 켜면 켜기 → 앱 열기 → 다시 읽기 순서로 부르고 켜짐이 된다")
  func bootSuccess() async {
    let fake = SimulatorClientFake(inventory: .sample)
    let model = LauncherModel(simulator: fake)
    await model.onAppear()

    await model.bootButtonTapped(SampleID.iPhoneOff)

    #expect(
      fake.calls == [.fetchInventory, .boot(SampleID.iPhoneOff), .openSimulatorApp, .fetchInventory]
    )
    #expect(Self.device(SampleID.iPhoneOff, in: model)?.state == .booted)
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.notice == nil)
  }

  @Test("켜는 동안 같은 기기를 다시 눌러도 한 번만 켠다")
  func bootSameDeviceTwiceBootsOnce() async {
    let fake = SimulatorClientFake(inventory: .sample)
    let model = LauncherModel(simulator: fake)
    await model.onAppear()

    fake.suspendBoots()
    let task = Task { await model.bootButtonTapped(SampleID.iPhoneOff) }
    await Self.waitUntil { fake.calls.contains(.boot(SampleID.iPhoneOff)) }
    #expect(model.busyDeviceIDs == [SampleID.iPhoneOff])

    await model.bootButtonTapped(SampleID.iPhoneOff)
    #expect(fake.calls.filter { $0 == .boot(SampleID.iPhoneOff) }.count == 1)

    fake.resumeBoots()
    await task.value
    #expect(fake.calls.filter { $0 == .boot(SampleID.iPhoneOff) }.count == 1)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("두 기기를 함께 켜면 둘 다 진행 중이 되고, 둘 다 켜진다")
  func bootTwoDevicesConcurrently() async {
    let fake = SimulatorClientFake(inventory: .sample)
    let model = LauncherModel(simulator: fake)
    await model.onAppear()

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
    let fake = SimulatorClientFake(inventory: .sample)
    fake.setBootError(.commandFailed)
    let model = LauncherModel(simulator: fake)
    await model.onAppear()

    await model.bootButtonTapped(SampleID.iPhoneOff)

    #expect(model.notice == .bootFailed(.commandFailed))
    #expect(fake.calls == [.fetchInventory, .boot(SampleID.iPhoneOff), .fetchInventory])
    #expect(Self.device(SampleID.iPhoneOff, in: model)?.state == .shutdown)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("켜기 실패 뒤 다시 읽기도 실패하면 켜기 실패 알림을 그대로 두고 목록을 유지한다")
  func bootFailureThenRefreshFailureKeepsBootNotice() async {
    let fake = SimulatorClientFake(inventory: .sample)
    let model = LauncherModel(simulator: fake)
    await model.onAppear()

    fake.setBootError(.deviceNotFound)
    fake.setFetchError(.commandFailed)
    await model.bootButtonTapped(SampleID.iPhoneOff)

    #expect(model.notice == .bootFailed(.deviceNotFound))
    #expect(model.listState == .loaded(DeviceList(inventory: .sample)))
    #expect(fake.calls == [.fetchInventory, .boot(SampleID.iPhoneOff), .fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("켜졌지만 앱을 열지 못하면 알리고, 기기는 켜짐으로 보인다")
  func openAppFailureAfterBoot() async {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.setOpenAppError(.simulatorAppNotFound)
    let model = LauncherModel(simulator: fake)
    await model.onAppear()

    await model.bootButtonTapped(SampleID.iPhoneOff)

    #expect(model.notice == .openAppFailed(.simulatorAppNotFound))
    #expect(Self.device(SampleID.iPhoneOff, in: model)?.state == .booted)
    #expect(fake.calls.last == .fetchInventory)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("켜는 동안 새로 고침해도 켜기는 이어지고, 끝나면 켜짐이 된다")
  func refreshDuringBoot() async {
    let fake = SimulatorClientFake(inventory: .sample)
    let model = LauncherModel(simulator: fake)
    await model.onAppear()

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
    let fake = SimulatorClientFake(inventory: .sample)
    let model = LauncherModel(simulator: fake)
    await model.onAppear()

    await model.shutdownButtonTapped(SampleID.iPhoneOn)

    #expect(fake.calls == [.fetchInventory, .shutdown(SampleID.iPhoneOn), .fetchInventory])
    #expect(Self.device(SampleID.iPhoneOn, in: model)?.state == .shutdown)
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.notice == nil)
  }

  @Test("끄기가 실패하면 알리고 목록을 다시 읽으며, 진행 중을 푼다")
  func shutdownFailureNotifiesAndReloads() async {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.setShutdownError(.commandFailed)
    let model = LauncherModel(simulator: fake)
    await model.onAppear()

    await model.shutdownButtonTapped(SampleID.iPhoneOn)

    #expect(model.notice == .shutdownFailed(.commandFailed))
    #expect(fake.calls == [.fetchInventory, .shutdown(SampleID.iPhoneOn), .fetchInventory])
    #expect(Self.device(SampleID.iPhoneOn, in: model)?.state == .booted)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  // MARK: - 조작할 수 없는 기기

  @Test("쓸 수 없는·켜진·목록에 없는 기기 켜기와 꺼진 기기 끄기는 아무것도 부르지 않는다")
  func invalidActionsCallNothing() async {
    let fake = SimulatorClientFake(inventory: .sample)
    let model = LauncherModel(simulator: fake)
    await model.onAppear()

    await model.bootButtonTapped(SampleID.unavailableIPhone)
    await model.bootButtonTapped(SampleID.iPhoneOn)
    await model.bootButtonTapped(SampleID.watch)
    await model.shutdownButtonTapped(SampleID.iPhoneOff)

    #expect(fake.calls == [.fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.notice == nil)
  }

  @Test("목록을 읽기 전에는 켜기·끄기가 아무것도 부르지 않는다")
  func actionsBeforeLoadCallNothing() async {
    let fake = SimulatorClientFake(inventory: .sample)
    let model = LauncherModel(simulator: fake)

    await model.bootButtonTapped(SampleID.iPhoneOff)
    await model.shutdownButtonTapped(SampleID.iPhoneOn)

    #expect(fake.calls.isEmpty)
  }

  // MARK: - 알림

  @Test("알림을 닫으면 알림이 사라진다")
  func noticeDismissedClearsNotice() async {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.setBootError(.commandFailed)
    let model = LauncherModel(simulator: fake)
    await model.onAppear()
    await model.bootButtonTapped(SampleID.iPhoneOff)
    #expect(model.notice != nil)

    model.noticeDismissed()

    #expect(model.notice == nil)
  }

  // MARK: - 문구

  @Test("모든 문구 함수가 모든 케이스에 비어 있지 않은 한국어를 돌려준다")
  func textsAreNonEmptyKorean() {
    for text in LauncherTextCatalog.all {
      #expect(!text.isEmpty)
      #expect(text.unicodeScalars.contains { (0xAC00 ... 0xD7A3).contains($0.value) }, "\(text)")
    }
    #expect(LauncherText.title(for: nil).isEmpty)
  }

  // MARK: - 도움 함수

  private static func device(_ id: VirtualDevice.ID, in model: LauncherModel) -> VirtualDevice? {
    guard case let .loaded(list) = model.listState else { return nil }
    return list.device(id: id)
  }

  /// 조건이 참이 될 때까지 다른 작업에 차례를 넘긴다.
  private static func waitUntil(_ condition: () -> Bool) async {
    while !condition() {
      await Task.yield()
    }
  }
}

/// `LauncherText` 가 돌려줄 수 있는 모든 문구 (알림 없음의 빈 제목 제외).
enum LauncherTextCatalog {
  static let errors: [SimulatorError] = [
    .developerToolsUnavailable, .deviceNotFound, .simulatorAppNotFound, .unexpectedOutput, .commandFailed,
  ]

  static let notices: [LauncherNotice] = [
    .refreshFailed(.commandFailed), .bootFailed(.commandFailed), .shutdownFailed(.commandFailed),
    .openAppFailed(.commandFailed),
  ]

  static let reasons: [VirtualDevice.UnavailableReason] = [
    .runtimeNotInstalled, .runtimeUnavailable, .deviceTypeNotSupported, .unknown,
  ]

  static let states: [VirtualDevice.State] = [.shutdown, .booting, .booted, .shuttingDown, .unknown]

  static let emptyReasons: [DeviceListEmptyReason] = [.noIOSRuntime, .noDevices]

  static var all: [String] {
    self.errors.map { LauncherText.message(for: $0) }
      + self.notices.map { LauncherText.title(for: $0) }
      + self.notices.map { LauncherText.message(for: $0) }
      + self.reasons.map { LauncherText.reason(for: $0) }
      + self.states.map { LauncherText.stateLabel(for: $0) }
      + self.emptyReasons.map { LauncherText.emptyTitle(for: $0) }
      + self.emptyReasons.map { LauncherText.emptyMessage(for: $0) }
      + [
        LauncherText.okButton, LauncherText.unavailableLabel, LauncherText.bootButton, LauncherText.shutdownButton,
        LauncherText.loading, LauncherText.loadFailedTitle, LauncherText.refreshButton, LauncherText.retryButton,
      ]
  }
}
