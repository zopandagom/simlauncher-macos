import AppBundleTesting
import Core
import DownloadTesting
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

@MainActor
struct LauncherOpenURLTests: LauncherModelTesting {
  static let raw = "myapp://item/1"
  static let link = DeepLink(raw)!

  // MARK: - 시트 열기·입력·닫기

  @Test("링크를 열 수 있는 기기(켜짐·꺼짐)에서 누르면 누른 시점의 기기로 빈 초안을 연다", arguments: [
    SampleID.iPhoneOn, SampleID.iPhoneOff,
  ])
  func buttonOpensDraft(id: VirtualDevice.ID) async {
    let (model, _) = await Self.loadedModel()

    model.openURLButtonTapped(id)

    #expect(model.openURLDraft?.deviceID == id)
    #expect(model.openURLDraft?.device == Self.label(id))
    #expect(model.openURLDraft?.text.isEmpty == true)
    #expect(model.openURLDraft?.problem == .empty)
    #expect(model.openURLDraft?.canSubmit == false)
  }

  @Test("쓸 수 없는·켜는 중·목록에 없는 기기와 목록을 읽기 전에는 시트를 열지 않는다")
  func buttonIgnoresBlockedDevices() async {
    let (model, simulator) = await Self.loadedModel()
    model.openURLButtonTapped(SampleID.unavailableIPhone)
    model.openURLButtonTapped(SampleID.watch)
    model.openURLButtonTapped(VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF"))
    #expect(model.openURLDraft == nil)

    simulator.setInventory(Self.inventory(SampleID.iPhoneOff, state: .booting))
    await model.refreshButtonTapped()
    model.openURLButtonTapped(SampleID.iPhoneOff)
    #expect(model.openURLDraft == nil)

    let beforeLoad = LauncherModel(
      simulator: SimulatorClientFake(inventory: .sample),
      appBundle: AppBundleClientFake(),
      download: DownloadClientFake()
    )
    beforeLoad.openURLButtonTapped(SampleID.iPhoneOn)
    #expect(beforeLoad.openURLDraft == nil)
  }

  @Test("작업이 진행 중인 기기에서는 시트를 열지 않는다")
  func buttonIgnoresBusyDevice() async {
    let (model, simulator) = await Self.loadedModel { $0.suspendBoots() }
    let boot = Task { await model.bootButtonTapped(SampleID.iPhoneOff) }
    await Self.waitUntil { simulator.calls.contains(.boot(SampleID.iPhoneOff)) }

    model.openURLButtonTapped(SampleID.iPhoneOff)
    #expect(model.openURLDraft == nil)

    simulator.resumeBoots()
    await boot.value
  }

  @Test("생성 시트·삭제 확인·다른 링크 시트가 열려 있으면 시트를 열지 않는다")
  func buttonIgnoresOtherPresentations() async {
    let (model, _) = await Self.loadedModel()

    model.createButtonTapped()
    model.openURLButtonTapped(SampleID.iPhoneOn)
    #expect(model.openURLDraft == nil)
    model.createCancelTapped()

    model.deleteButtonTapped(SampleID.iPhoneOff)
    model.openURLButtonTapped(SampleID.iPhoneOn)
    #expect(model.openURLDraft == nil)
    model.confirmationDismissed()

    model.openURLButtonTapped(SampleID.iPhoneOn)
    model.openURLButtonTapped(SampleID.iPhoneOff)
    #expect(model.openURLDraft?.deviceID == SampleID.iPhoneOn)
  }

  @Test("링크 시트가 열린 동안 + 버튼·생성 시트·삭제·초기화 확인을 받지 않는다")
  func draftBlocksOtherPresentations() async {
    let (model, _) = await Self.loadedModel()
    model.openURLButtonTapped(SampleID.iPhoneOn)

    #expect(!model.canCreateDevice)
    model.createButtonTapped()
    #expect(model.createDraft == nil)
    model.deleteButtonTapped(SampleID.iPhoneOff)
    model.eraseButtonTapped(SampleID.iPhoneOff)
    #expect(model.pendingConfirmation == nil)

    model.openURLCancelTapped()
    #expect(model.canCreateDevice)
  }

  @Test("입력을 바꾸면 초안의 글자와 문제가 바뀌고, 초안이 없으면 무시한다")
  func textChangeUpdatesProblem() async {
    let (model, _) = await Self.loadedModel()
    model.openURLTextChanged(Self.raw)
    #expect(model.openURLDraft == nil)

    model.openURLButtonTapped(SampleID.iPhoneOn)
    model.openURLTextChanged("example.com")
    #expect(model.openURLDraft?.text == "example.com")
    #expect(model.openURLDraft?.problem == .missingScheme)
    #expect(model.openURLDraft?.canSubmit == false)

    model.openURLTextChanged("myapp://a b")
    #expect(model.openURLDraft?.problem == .malformed)

    model.openURLTextChanged(Self.raw)
    #expect(model.openURLDraft?.problem == nil)
    #expect(model.openURLDraft?.link == Self.link)
    #expect(model.openURLDraft?.canSubmit == true)
  }

  @Test("취소와 닫기는 초안을 지우고, 두 번 불려도 무해하다")
  func cancelAndDismissClearDraft() async {
    let (model, simulator) = await Self.loadedModel()
    model.openURLButtonTapped(SampleID.iPhoneOn)
    model.openURLCancelTapped()
    model.openURLCancelTapped()
    #expect(model.openURLDraft == nil)

    model.openURLButtonTapped(SampleID.iPhoneOn)
    model.openURLSheetDismissed()
    model.openURLSheetDismissed()
    #expect(model.openURLDraft == nil)
    #expect(simulator.calls == [.fetchInventory])
  }

  // MARK: - 열기 성공

  @Test("켜진 기기는 켜지 않고 앱 열기 → 링크 열기 → 다시 읽기이며 시트가 닫히고 알림이 없다")
  func openOnBootedDevice() async {
    let (model, simulator) = await Self.open(Self.raw, on: SampleID.iPhoneOn)

    #expect(simulator.calls == [
      .fetchInventory, .openSimulatorApp, .openURL(Self.link, SampleID.iPhoneOn), .fetchInventory,
    ])
    #expect(model.openURLDraft == nil)
    #expect(model.notices.isEmpty)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("꺼진 기기는 켜기 → 앱 열기 → 링크 열기 → 다시 읽기이고 끝나면 켜짐이다")
  func openOnShutdownDevice() async {
    let (model, simulator) = await Self.open(Self.raw, on: SampleID.iPhoneOff)

    #expect(simulator.calls == [
      .fetchInventory, .boot(SampleID.iPhoneOff), .openSimulatorApp, .openURL(Self.link, SampleID.iPhoneOff),
      .fetchInventory,
    ])
    #expect(Self.device(SampleID.iPhoneOff, in: model)?.state == .booted)
    #expect(model.notices.isEmpty)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("앞뒤 공백·개행을 뺀 링크를 연다")
  func opensTrimmedLink() async throws {
    let (_, simulator) = await Self.open("  https://example.com \n", on: SampleID.iPhoneOn)

    #expect(try simulator.calls.contains(.openURL(#require(DeepLink("https://example.com")), SampleID.iPhoneOn)))
  }

  // MARK: - 명령 전 거절

  @Test("문제가 있는 입력은 아무것도 부르지 않고 시트와 입력을 그대로 둔다", arguments: ["", "  ", "example.com", "myapp://a b"])
  func problemInputDoesNothing(text: String) async {
    let (model, simulator) = await Self.loadedModel()
    model.openURLButtonTapped(SampleID.iPhoneOn)
    model.openURLTextChanged(text)

    await model.openURLConfirmTapped()

    #expect(model.openURLDraft?.text == text)
    #expect(simulator.calls == [.fetchInventory])
    #expect(model.notices.isEmpty)
  }

  @Test("초안이 없으면 확인은 아무것도 하지 않는다")
  func confirmWithoutDraftDoesNothing() async {
    let (model, simulator) = await Self.loadedModel()

    await model.openURLConfirmTapped()

    #expect(simulator.calls == [.fetchInventory])
    #expect(model.notices.isEmpty)
  }

  @Test("시트를 연 사이 기기가 목록에서 사라지면 찾을 수 없다고 알리고 명령을 실행하지 않는다")
  func deviceRemovedBeforeConfirm() async {
    let (model, simulator) = await Self.loadedModel()
    let id = SampleID.iPhoneOff
    model.openURLButtonTapped(id)
    model.openURLTextChanged(Self.raw)
    simulator.setInventory(Self.inventory(removing: id))
    await model.refreshButtonTapped()

    await model.openURLConfirmTapped()

    #expect(model.notices.map(\.notice) == [.openURLFailed(Self.label(id), .simulator(.deviceNotFound))])
    #expect(simulator.calls == [.fetchInventory, .fetchInventory])
    #expect(model.openURLDraft == nil)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("시트를 연 사이 기기가 켜는 중이 되면 상태가 바뀌는 중이라고 알리고 명령을 실행하지 않는다")
  func deviceBootingBeforeConfirm() async {
    let (model, simulator) = await Self.loadedModel()
    let id = SampleID.iPhoneOff
    model.openURLButtonTapped(id)
    model.openURLTextChanged(Self.raw)
    simulator.setInventory(Self.inventory(id, state: .booting))
    await model.refreshButtonTapped()

    await model.openURLConfirmTapped()

    #expect(model.notices.map(\.notice) == [.openURLFailed(Self.label(id), .deviceNotReady(.stateChanging))])
    #expect(simulator.calls == [.fetchInventory, .fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  // MARK: - 명령 실패

  @Test("켜기가 실패하면 알리고 링크를 열지 않으며, 다시 읽고 진행 중을 푼다")
  func bootFailure() async {
    let (model, simulator) = await Self.open(Self.raw, on: SampleID.iPhoneOff) { $0.setBootError(.commandFailed) }

    #expect(model.notices.map(\.notice) == [.bootFailed(Self.label(SampleID.iPhoneOff), .commandFailed)])
    #expect(simulator.calls == [.fetchInventory, .boot(SampleID.iPhoneOff), .fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("Simulator 앱을 열지 못해도 알리고 링크는 연다 (켜진 기기도 앱을 연다)", arguments: [
    SampleID.iPhoneOff, SampleID.iPhoneOn,
  ])
  func openAppFailureContinues(id: VirtualDevice.ID) async {
    let (model, simulator) = await Self.open(Self.raw, on: id) { $0.setOpenAppError(.simulatorAppNotFound) }

    #expect(model.notices.map(\.notice) == [.openAppFailed(Self.label(id), .simulatorAppNotFound)])
    #expect(simulator.calls.suffix(3) == [.openSimulatorApp, .openURL(Self.link, id), .fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("링크 열기가 실패하면 누른 시점의 기기로 원인을 알리고 다시 읽는다", arguments: [
    SimulatorError.urlNotHandled, .invalidURL, .deviceNotBooted, .commandFailed,
  ])
  func openURLFailure(error: SimulatorError) async {
    let (model, simulator) = await Self.open(Self.raw, on: SampleID.iPhoneOn) { $0.setOpenURLError(error) }

    #expect(model.notices.map(\.notice) == [.openURLFailed(Self.label(SampleID.iPhoneOn), .simulator(error))])
    #expect(simulator.calls.suffix(2) == [.openURL(Self.link, SampleID.iPhoneOn), .fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  // MARK: - 진행 중

  @Test("링크를 여는 동안 그 기기는 링크 열기 중이고 설치·켜기를 받지 않으며, 다른 기기 설치는 되고, 끝나면 풀린다")
  func openingBlocksSameDeviceOnly() async {
    let appBundle = AppBundleClientFake()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle) { $0.suspendOpenURLs() }
    let id = SampleID.iPhoneOff
    model.openURLButtonTapped(id)
    model.openURLTextChanged(Self.raw)
    let open = Task { await model.openURLConfirmTapped() }
    await Self.waitUntil { simulator.calls.contains(.openURL(Self.link, id)) }

    #expect(model.activity.task(on: id) == .openURL)
    let calls = simulator.calls.count
    let attempts = Self.start {
      await model.appFileSelected(LauncherInstallTests.picked, for: id)
      await model.bootButtonTapped(id)
    }
    await Self.waitUntil { attempts.isFinished || simulator.calls.count > calls }
    #expect(simulator.calls.count == calls)
    #expect(appBundle.calls.isEmpty)
    model.openURLButtonTapped(id)
    #expect(model.openURLDraft == nil)

    await model.appFileSelected(LauncherInstallTests.picked, for: SampleID.iPhoneOn)
    #expect(simulator.calls.contains(.launch(LauncherInstallTests.sample.bundleID, SampleID.iPhoneOn)))
    #expect(model.activity.task(on: id) == .openURL)

    simulator.resumeOpenURLs()
    await open.value
    #expect(model.activity.task(on: id) == nil)
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.notices.isEmpty)
  }

  @Test("확인을 연달아 눌러도 링크는 한 번만 연다")
  func doubleConfirmOpensOnce() async {
    let (model, simulator) = await Self.loadedModel()
    model.openURLButtonTapped(SampleID.iPhoneOn)
    model.openURLTextChanged(Self.raw)

    let first = Task { await model.openURLConfirmTapped() }
    let second = Task { await model.openURLConfirmTapped() }
    await first.value
    await second.value

    #expect(simulator.calls.filter { $0 == .openURL(Self.link, SampleID.iPhoneOn) }.count == 1)
    #expect(model.notices.isEmpty)
  }
}

extension LauncherOpenURLTests {
  /// 목록을 읽은 Model 에서 시트를 열고 입력한 뒤 열기까지 끝낸다.
  static func open(
    _ text: String,
    on id: VirtualDevice.ID,
    _ configure: (SimulatorClientFake) -> Void = { _ in }
  ) async -> (LauncherModel, SimulatorClientFake) {
    let (model, simulator) = await Self.loadedModel(configure)
    model.openURLButtonTapped(id)
    model.openURLTextChanged(text)
    await model.openURLConfirmTapped()
    return (model, simulator)
  }
}
