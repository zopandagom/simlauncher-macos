import AppBundleTesting
import AppLogTesting
import Core
import DownloadTesting
import SimulatorInterface
import SimulatorTesting
import Testing
import WorkspaceTesting
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
    let loaded = await Self.loadedModels()
    let sheets = loaded.sheets

    sheets.openURLTapped(id)

    #expect(sheets.openURLDraft?.deviceID == id)
    #expect(sheets.openURLDraft?.device == Self.label(id))
    #expect(sheets.openURLDraft?.text.isEmpty == true)
    #expect(sheets.openURLDraft?.problem == .empty)
    #expect(sheets.openURLDraft?.canSubmit == false)
  }

  @Test("쓸 수 없는·켜는 중·목록에 없는 기기와 목록을 읽기 전에는 시트를 열지 않는다")
  func buttonIgnoresBlockedDevices() async {
    let loaded = await Self.loadedModels()
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    sheets.openURLTapped(SampleID.unavailableIPhone)
    sheets.openURLTapped(SampleID.watch)
    sheets.openURLTapped(VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF"))
    #expect(sheets.openURLDraft == nil)

    simulator.setInventory(Self.inventory(SampleID.iPhoneOff, state: .booting))
    await model.refreshButtonTapped()
    sheets.openURLTapped(SampleID.iPhoneOff)
    #expect(sheets.openURLDraft == nil)

    let beforeLoad = LauncherModel(
      simulator: SimulatorClientFake(inventory: .sample),
      appBundle: AppBundleClientFake(),
      download: DownloadClientFake(),
      workspace: WorkspaceClientFake(),
      appLog: AppLogClientFake()
    )
    let beforeLoadSheets = Self.appSheets(simulator: SimulatorClientFake(inventory: .sample), launcher: beforeLoad)
    beforeLoadSheets.openURLTapped(SampleID.iPhoneOn)
    #expect(beforeLoadSheets.openURLDraft == nil)
  }

  @Test("작업이 진행 중인 기기에서는 시트를 열지 않는다")
  func buttonIgnoresBusyDevice() async {
    let loaded = await Self.loadedModels { $0.suspendBoots() }
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    let boot = Task { await model.bootButtonTapped(SampleID.iPhoneOff) }
    await Self.waitUntil { simulator.calls.contains(.boot(SampleID.iPhoneOff)) }

    sheets.openURLTapped(SampleID.iPhoneOff)
    #expect(sheets.openURLDraft == nil)

    simulator.resumeBoots()
    await boot.value
  }

  @Test("생성 시트·삭제 확인·다른 링크 시트가 열려 있으면 시트를 열지 않는다")
  func buttonIgnoresOtherPresentations() async {
    let loaded = await Self.loadedModels()
    let model = loaded.model
    let sheets = loaded.sheets

    model.createButtonTapped()
    sheets.openURLTapped(SampleID.iPhoneOn)
    #expect(sheets.openURLDraft == nil)
    model.createCancelTapped()

    model.deleteButtonTapped(SampleID.iPhoneOff)
    sheets.openURLTapped(SampleID.iPhoneOn)
    #expect(sheets.openURLDraft == nil)
    model.confirmationDismissed()

    sheets.openURLTapped(SampleID.iPhoneOn)
    sheets.openURLTapped(SampleID.iPhoneOff)
    #expect(sheets.openURLDraft?.deviceID == SampleID.iPhoneOn)
  }

  @Test("링크 시트가 열린 동안 + 버튼·생성 시트·삭제·초기화 확인을 받지 않는다")
  func draftBlocksOtherPresentations() async {
    let loaded = await Self.loadedModels()
    let model = loaded.model
    let sheets = loaded.sheets
    sheets.openURLTapped(SampleID.iPhoneOn)

    #expect(!model.canCreateDevice)
    model.createButtonTapped()
    #expect(model.createDraft == nil)
    model.deleteButtonTapped(SampleID.iPhoneOff)
    model.eraseButtonTapped(SampleID.iPhoneOff)
    #expect(model.pendingConfirmation == nil)

    sheets.openURLCancelTapped()
    #expect(model.canCreateDevice)
  }

  @Test("입력을 바꾸면 초안의 글자와 문제가 바뀌고, 초안이 없으면 무시한다")
  func textChangeUpdatesProblem() async {
    let loaded = await Self.loadedModels()
    let sheets = loaded.sheets
    sheets.openURLTextChanged(Self.raw)
    #expect(sheets.openURLDraft == nil)

    sheets.openURLTapped(SampleID.iPhoneOn)
    sheets.openURLTextChanged("example.com")
    #expect(sheets.openURLDraft?.text == "example.com")
    #expect(sheets.openURLDraft?.problem == .missingScheme)
    #expect(sheets.openURLDraft?.canSubmit == false)

    sheets.openURLTextChanged("myapp://a b")
    #expect(sheets.openURLDraft?.problem == .malformed)

    sheets.openURLTextChanged(Self.raw)
    #expect(sheets.openURLDraft?.problem == nil)
    #expect(sheets.openURLDraft?.link == Self.link)
    #expect(sheets.openURLDraft?.canSubmit == true)
  }

  @Test("취소와 닫기는 초안을 지우고, 두 번 불려도 무해하다")
  func cancelAndDismissClearDraft() async {
    let loaded = await Self.loadedModels()
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    sheets.openURLTapped(SampleID.iPhoneOn)
    sheets.openURLCancelTapped()
    sheets.openURLCancelTapped()
    #expect(sheets.openURLDraft == nil)

    sheets.openURLTapped(SampleID.iPhoneOn)
    sheets.openURLSheetDismissed()
    sheets.openURLSheetDismissed()
    #expect(sheets.openURLDraft == nil)
    #expect(simulator.calls == [.fetchInventory])
  }

  // MARK: - 열기 성공

  @Test("켜진 기기는 켜지 않고 앱 열기 → 링크 열기 → 다시 읽기이며 시트가 닫히고 알림이 없다")
  func openOnBootedDevice() async {
    let loaded = await Self.open(Self.raw, on: SampleID.iPhoneOn)
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator

    #expect(simulator.calls == [
      .fetchInventory, .openSimulatorApp, .openURL(Self.link, SampleID.iPhoneOn), .fetchInventory,
    ])
    #expect(sheets.openURLDraft == nil)
    #expect(model.notices.isEmpty)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("꺼진 기기는 켜기 → 앱 열기 → 링크 열기 → 다시 읽기이고 끝나면 켜짐이다")
  func openOnShutdownDevice() async {
    let loaded = await Self.open(Self.raw, on: SampleID.iPhoneOff)
    let model = loaded.model
    let simulator = loaded.simulator

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
    let loaded = await Self.open("  https://example.com \n", on: SampleID.iPhoneOn)
    let simulator = loaded.simulator

    #expect(try simulator.calls.contains(.openURL(#require(DeepLink("https://example.com")), SampleID.iPhoneOn)))
  }

  // MARK: - 명령 전 거절

  @Test("문제가 있는 입력은 아무것도 부르지 않고 시트와 입력을 그대로 둔다", arguments: ["", "  ", "example.com", "myapp://a b"])
  func problemInputDoesNothing(text: String) async {
    let loaded = await Self.loadedModels()
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    sheets.openURLTapped(SampleID.iPhoneOn)
    sheets.openURLTextChanged(text)

    await sheets.openURLConfirmTapped()

    #expect(sheets.openURLDraft?.text == text)
    #expect(simulator.calls == [.fetchInventory])
    #expect(model.notices.isEmpty)
  }

  @Test("초안이 없으면 확인은 아무것도 하지 않는다")
  func confirmWithoutDraftDoesNothing() async {
    let loaded = await Self.loadedModels()
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator

    await sheets.openURLConfirmTapped()

    #expect(simulator.calls == [.fetchInventory])
    #expect(model.notices.isEmpty)
  }

  @Test("시트를 연 사이 기기가 목록에서 사라지면 찾을 수 없다고 알리고 명령을 실행하지 않는다")
  func deviceRemovedBeforeConfirm() async {
    let loaded = await Self.loadedModels()
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    let id = SampleID.iPhoneOff
    sheets.openURLTapped(id)
    sheets.openURLTextChanged(Self.raw)
    simulator.setInventory(Self.inventory(removing: id))
    await model.refreshButtonTapped()

    await sheets.openURLConfirmTapped()

    #expect(model.notices.map(\.notice) == [.openURLFailed(Self.label(id), .simulator(.deviceNotFound))])
    #expect(simulator.calls == [.fetchInventory, .fetchInventory])
    #expect(sheets.openURLDraft == nil)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("시트를 연 사이 기기가 켜는 중이 되면 상태가 바뀌는 중이라고 알리고 명령을 실행하지 않는다")
  func deviceBootingBeforeConfirm() async {
    let loaded = await Self.loadedModels()
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    let id = SampleID.iPhoneOff
    sheets.openURLTapped(id)
    sheets.openURLTextChanged(Self.raw)
    simulator.setInventory(Self.inventory(id, state: .booting))
    await model.refreshButtonTapped()

    await sheets.openURLConfirmTapped()

    #expect(model.notices.map(\.notice) == [.openURLFailed(Self.label(id), .deviceNotReady(.stateChanging))])
    #expect(simulator.calls == [.fetchInventory, .fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }
}

extension LauncherOpenURLTests {
  /// 목록을 읽은 Model 에서 시트를 열고 입력한 뒤 열기까지 끝낸다.
  static func open(
    _ text: String,
    on id: VirtualDevice.ID,
    _ configure: (SimulatorClientFake) -> Void = { _ in }
  ) async -> LoadedModels {
    let loaded = await Self.loadedModels(configure)
    loaded.sheets.openURLTapped(id)
    loaded.sheets.openURLTextChanged(text)
    await loaded.sheets.openURLConfirmTapped()
    return loaded
  }
}
