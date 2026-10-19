import Core
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

@MainActor
struct LauncherCreateTests: LauncherModelTesting {
  // MARK: - 시트 열기·닫기

  @Test("+ 를 누르면 최신 런타임, 그 첫 기기 종류, 종류 이름으로 초안을 열고 아무것도 부르지 않는다")
  func createButtonOpensDraftWithDefaults() async throws {
    let (model, fake) = await Self.loadedModel()
    #expect(model.canCreateDevice)

    model.createButtonTapped()

    let draft = try #require(model.createDraft)
    #expect(draft.runtimeID == SampleRuntime.iOS27.id)
    #expect(draft.deviceTypeID == SampleDeviceType.iPhone17Pro.id)
    #expect(draft.name == "iPhone 17 Pro")
    #expect(draft.options == DeviceCreationOptions(inventory: .sample))
    #expect(draft.canSubmit)
    #expect(model.canCreateDevice == false)
    #expect(fake.calls == [.fetchInventory])
  }

  @Test("목록을 읽기 전이나 만들 수 있는 런타임이 없으면 + 가 비활성이고 초안이 열리지 않는다")
  func cannotCreateBeforeLoadOrWithoutRuntime() async {
    let before = LauncherModel(simulator: SimulatorClientFake(inventory: .sample))
    #expect(before.canCreateDevice == false)
    before.createButtonTapped()
    #expect(before.createDraft == nil)

    let noRuntime = LauncherModel(simulator: SimulatorClientFake(inventory: .noRuntime))
    await noRuntime.onAppear()
    #expect(noRuntime.canCreateDevice == false)
    noRuntime.createButtonTapped()
    #expect(noRuntime.createDraft == nil)
  }

  @Test("기기가 없어도 만들 수 있는 런타임이 있으면 + 를 누를 수 있다")
  func canCreateWithNoDevices() async {
    let model = LauncherModel(simulator: SimulatorClientFake(inventory: .noDevices))
    await model.onAppear()

    model.createButtonTapped()

    #expect(model.createDraft?.deviceTypeID == SampleDeviceType.iPhone17Pro.id)
  }

  @Test("취소와 시트 닫힘은 초안을 지우고 아무것도 부르지 않는다")
  func cancelAndDismissClearDraft() async {
    let (model, fake) = await Self.loadedModel()

    model.createButtonTapped()
    model.createCancelTapped()
    #expect(model.createDraft == nil)

    model.createButtonTapped()
    model.createSheetDismissed()
    #expect(model.createDraft == nil)
    #expect(model.canCreateDevice)
    #expect(fake.calls == [.fetchInventory])
  }

  // MARK: - 초안 고치기

  @Test("런타임을 바꾸면 지원하는 종류는 유지하고, 아니면 첫 종류로 바꾸며 이름이 따라간다")
  func runtimeChangeKeepsOrResetsDeviceType() async throws {
    let (model, _) = await Self.loadedModel()
    model.createButtonTapped()

    model.createRuntimeChanged(SampleRuntime.iOS26.id)
    var draft = try #require(model.createDraft)
    #expect(draft.runtimeID == SampleRuntime.iOS26.id)
    #expect(draft.deviceTypeID == SampleDeviceType.iPhone17.id)
    #expect(draft.name == "iPhone 17")
    #expect(draft.deviceTypes == [SampleDeviceType.iPhone17, SampleDeviceType.iPhone16, SampleDeviceType.iPadA16])

    model.createDeviceTypeChanged(SampleDeviceType.iPadA16.id)
    model.createRuntimeChanged(SampleRuntime.iOS27.id)
    draft = try #require(model.createDraft)
    #expect(draft.deviceTypeID == SampleDeviceType.iPadA16.id)
    #expect(draft.name == "iPad (A16)")
  }

  @Test("종류를 바꾸면 이름이 따라가고, 이름을 고친 뒤에는 그대로다")
  func deviceTypeChangeFollowsNameUntilEdited() async throws {
    let (model, _) = await Self.loadedModel()
    model.createButtonTapped()

    model.createDeviceTypeChanged(SampleDeviceType.iPadA16.id)
    #expect(model.createDraft?.name == "iPad (A16)")

    model.createNameChanged("내 iPad")
    model.createDeviceTypeChanged(SampleDeviceType.iPhone17.id)
    model.createRuntimeChanged(SampleRuntime.iOS26.id)
    let draft = try #require(model.createDraft)
    #expect(draft.name == "내 iPad")
    #expect(draft.isNameEdited)
    #expect(draft.deviceTypeID == SampleDeviceType.iPhone17.id)
  }

  @Test("목록에 없는 런타임과, 지금 런타임이 지원하지 않는 종류는 무시한다")
  func unknownSelectionsAreIgnored() async throws {
    let (model, _) = await Self.loadedModel()
    model.createButtonTapped()
    let before = try #require(model.createDraft)

    model.createRuntimeChanged(SampleRuntime.watchOS27.id)
    model.createRuntimeChanged(DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-99-0"))
    model.createDeviceTypeChanged(SampleDeviceType.iPhone16.id)
    model.createDeviceTypeChanged(SampleDeviceType.watchSeries11.id)

    #expect(model.createDraft == before)
  }

  @Test("초안이 없으면 고치기 이벤트는 아무것도 하지 않는다")
  func editsWithoutDraftDoNothing() async {
    let (model, _) = await Self.loadedModel()

    model.createNameChanged("이름")
    model.createRuntimeChanged(SampleRuntime.iOS26.id)
    model.createDeviceTypeChanged(SampleDeviceType.iPhone17.id)

    #expect(model.createDraft == nil)
  }

  @Test(
    "이름에 문제가 있으면 만들 수 없고, 만들기를 눌러도 초안을 유지하며 아무것도 부르지 않는다",
    arguments: [
      ("   ", DeviceNameProblem.empty),
      ("a\nb", .containsControlCharacter),
      (String(repeating: "가", count: DeviceName.maxLength + 1), .tooLong),
    ]
  )
  func invalidNameBlocksSubmit(name: String, problem: DeviceNameProblem) async {
    let (model, fake) = await Self.loadedModel()
    model.createButtonTapped()

    model.createNameChanged(name)
    #expect(model.createDraft?.nameProblem == problem)
    #expect(model.createDraft?.canSubmit == false)
    await model.createConfirmTapped()

    #expect(model.createDraft?.name == name)
    #expect(fake.calls == [.fetchInventory])
  }

  // MARK: - 만들기

  @Test("만들면 초안을 바로 닫고, 만드는 동안 + 가 비활성이며, 정리한 이름으로 만든 뒤 다시 읽는다")
  func createSuccess() async {
    let (model, fake) = await Self.loadedModel()
    model.createButtonTapped()
    model.createDeviceTypeChanged(SampleDeviceType.iPadA16.id)
    model.createNameChanged("  테스트 iPad  ")

    fake.suspendCreates()
    let task = Task { await model.createConfirmTapped() }
    await Self.waitUntil { fake.calls.count == 2 }
    #expect(model.createDraft == nil)
    #expect(model.isCreating)
    #expect(model.canCreateDevice == false)

    fake.resumeCreates()
    await task.value
    #expect(
      fake.calls == [
        .fetchInventory,
        .create(name: "테스트 iPad", deviceType: SampleDeviceType.iPadA16.id, runtime: SampleRuntime.iOS27.id),
        .fetchInventory,
      ]
    )
    let created = VirtualDevice.ID("00000000-0000-0000-0001-000000000001")
    #expect(Self.device(created, in: model)?.name == "테스트 iPad")
    #expect(model.isCreating == false)
    #expect(model.canCreateDevice)
    #expect(model.notices.isEmpty)
  }

  @Test("- 로 시작하는 이름도 Model 은 막지 않고 그대로 넘긴다")
  func dashNameIsPassedThrough() async {
    let (model, fake) = await Self.loadedModel()
    model.createButtonTapped()
    model.createNameChanged("-h")

    await model.createConfirmTapped()

    #expect(fake.calls.contains(.create(
      name: "-h",
      deviceType: SampleDeviceType.iPhone17Pro.id,
      runtime: SampleRuntime.iOS27.id
    )))
  }

  @Test("만들기가 실패하면 정리한 이름과 런타임 이름으로 알리고 다시 읽는다")
  func createFailureNotifiesAndReloads() async {
    let (model, fake) = await Self.loadedModel { $0.setCreateError(.creationOptionUnavailable) }
    model.createButtonTapped()
    model.createNameChanged(" 새 기기 ")

    await model.createConfirmTapped()

    let label = LauncherNotice.Device(name: "새 기기", runtimeName: "iOS 27.0")
    #expect(model.notices.map(\.notice) == [.createFailed(label, .creationOptionUnavailable)])
    #expect(fake.calls.last == .fetchInventory)
    #expect(fake.calls.count == 3)
    #expect(model.isCreating == false)
    #expect(model.createDraft == nil)
  }

  @Test("만드는 동안 다시 만들기·+ 를 눌러도 한 번만 만든다")
  func secondCreateWhileCreatingIsIgnored() async {
    let (model, fake) = await Self.loadedModel()
    model.createButtonTapped()

    fake.suspendCreates()
    let task = Task { await model.createConfirmTapped() }
    await Self.waitUntil { fake.calls.count == 2 }
    await model.createConfirmTapped()
    model.createButtonTapped()
    #expect(model.createDraft == nil)

    fake.resumeCreates()
    await task.value
    let creates = fake.calls.filter {
      if case .create = $0 {
        true
      } else {
        false
      }
    }
    #expect(creates.count == 1)
  }

  // MARK: - 선택지 유지

  @Test("다시 읽기가 실패해도 생성 선택지를 유지한다")
  func creationOptionsKeptOnRefreshFailure() async {
    let (model, fake) = await Self.loadedModel()
    let options = model.creationOptions
    #expect(options == DeviceCreationOptions(inventory: .sample))

    fake.setFetchError(.commandFailed)
    await model.refreshButtonTapped()

    #expect(model.creationOptions == options)
    #expect(model.canCreateDevice)
  }

  @Test("켜기·끄기·삭제 뒤 다시 읽어도 생성 선택지가 처음과 같고 + 를 누를 수 있다")
  func creationOptionsSurviveDeviceActions() async {
    let (model, _) = await Self.loadedModel()
    let options = model.creationOptions

    await model.bootButtonTapped(SampleID.iPhoneOff)
    #expect(model.creationOptions == options)
    #expect(model.canCreateDevice)

    await model.shutdownButtonTapped(SampleID.iPhoneOn)
    #expect(model.creationOptions == options)

    model.deleteButtonTapped(SampleID.iPadOff)
    if let confirmation = model.pendingConfirmation {
      await model.confirmationConfirmed(confirmation)
    }
    #expect(Self.device(SampleID.iPadOff, in: model) == nil)
    #expect(model.creationOptions == options)
    #expect(model.canCreateDevice)
  }
}

// MARK: - 만들 수 없는 이유

extension LauncherCreateTests {
  @Test("만들 수 있는 기기 종류가 없으면 빈 이유가 그것이고, + 를 쓸 수 없는 이유를 보이며 초안이 열리지 않는다")
  func noCreatableDeviceTypeShowsReason() async {
    let model = LauncherModel(simulator: SimulatorClientFake(inventory: .noCreatableDeviceType))
    await model.onAppear()

    guard case let .loaded(list) = model.listState else {
      Issue.record("목록을 읽지 못했다")
      return
    }
    #expect(list.emptyReason == .noCreatableDeviceType)
    #expect(model.canCreateDevice == false)
    #expect(model.isCreationUnavailable)
    model.createButtonTapped()
    #expect(model.createDraft == nil)
  }

  @Test("기기는 있지만 만들 수 있는 종류가 없으면 목록을 보이고 + 를 쓸 수 없는 이유를 보인다")
  func devicesWithoutCreatableTypeShowsReason() async {
    let sample = DeviceInventory.sample
    let inventory = DeviceInventory(devices: sample.devices, runtimes: sample.runtimes, deviceTypes: [])
    let model = LauncherModel(simulator: SimulatorClientFake(inventory: inventory))
    await model.onAppear()

    guard case let .loaded(list) = model.listState else {
      Issue.record("목록을 읽지 못했다")
      return
    }
    #expect(list.emptyReason == nil)
    #expect(model.isCreationUnavailable)
    #expect(model.canCreateDevice == false)
  }

  @Test("만들 수 있는 종류가 있으면 + 를 쓸 수 없는 이유가 없다")
  func sampleIsNotCreationUnavailable() async {
    let (model, _) = await Self.loadedModel()

    #expect(model.isCreationUnavailable == false)
  }

  @Test("목록을 읽기 전에는 + 를 쓸 수 없는 이유를 보이지 않는다 (로딩 표시가 보인다)")
  func notCreationUnavailableBeforeLoad() {
    let model = LauncherModel(simulator: SimulatorClientFake(inventory: .noCreatableDeviceType))

    #expect(model.canCreateDevice == false)
    #expect(model.isCreationUnavailable == false)
  }

  @Test("만드는 중에는 + 가 비활성이지만 쓸 수 없는 이유는 보이지 않는다 (진행 표시가 보인다)")
  func notCreationUnavailableWhileCreating() async {
    let (model, fake) = await Self.loadedModel()
    model.createButtonTapped()

    fake.suspendCreates()
    let task = Task { await model.createConfirmTapped() }
    await Self.waitUntil { model.isCreating }
    #expect(model.canCreateDevice == false)
    #expect(model.isCreationUnavailable == false)

    fake.resumeCreates()
    await task.value
  }
}
