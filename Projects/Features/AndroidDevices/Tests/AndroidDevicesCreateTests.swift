import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 만들기 시트와 만들기.
@MainActor
struct AndroidDevicesCreateTests: AndroidDevicesTesting {
  @Test("+ 는 가장 높은 API·휴대전화·빈 이름의 초안을 연다")
  func createButtonOpensDraft() async {
    let setup = await Self.loadedFixture()
    setup.model.createButtonTapped()
    let draft = setup.model.creationDraft
    #expect(draft?.image == .sample)
    #expect(draft?.profile == .phone)
    #expect(draft?.name.isEmpty == true)
    #expect(draft?.isNameEdited == false)
    #expect(draft?.canSubmit == false)
    #expect(!setup.model.canCreateDevice)
  }

  @Test("만들 이미지가 없거나 목록을 읽기 전이면 시트를 열지 않는다")
  func createButtonIgnored() async {
    let empty = await Self.loadedFixture(AndroidDeviceInventory(devices: [], creationOptions: .emptySample))
    empty.model.createButtonTapped()
    #expect(empty.model.creationDraft == nil)
    let notLoaded = Self.fixture()
    notLoaded.model.createButtonTapped()
    #expect(notLoaded.model.creationDraft == nil)
  }

  @Test("이름·이미지·화면 모양을 바꾸고, 선택지에 없는 값은 무시한다")
  func draftChanges() async {
    let setup = await Self.loadedFixture()
    setup.model.createButtonTapped()
    setup.model.creationNameChanged("  ")
    #expect(setup.model.creationDraft?.nameProblem == .empty)
    #expect(setup.model.creationDraft?.isNameEdited == true)
    setup.model.creationNameChanged("한 줄\n두 줄")
    #expect(setup.model.creationDraft?.nameProblem == .containsControlCharacter)
    setup.model.creationNameChanged("테스트 폰")
    #expect(setup.model.creationDraft?.nameProblem == nil)
    setup.model.creationImageChanged(.olderSample)
    #expect(setup.model.creationDraft?.image == .olderSample)
    let unknown = AndroidSystemImageRef(apiFolder: "android-30", tag: "google_apis", abi: "arm64-v8a")
    if let unknown {
      setup.model.creationImageChanged(unknown)
    }
    #expect(setup.model.creationDraft?.image == .olderSample)
    setup.model.creationProfileChanged(.tablet)
    #expect(setup.model.creationDraft?.profile == .tablet)
    #expect(setup.model.creationDraft?.canSubmit == true)
  }

  @Test("만들기: 시트를 닫고, 앞뒤 공백을 뺀 이름으로 만든 뒤 다시 읽어 새 기기를 고른다")
  func createSucceeds() async {
    let setup = await Self.loadedFixture(.emptySample)
    setup.model.createButtonTapped()
    setup.model.creationNameChanged("  내 폰 ")
    setup.model.creationProfileChanged(.smallPhone)
    await setup.model.creationConfirmTapped()
    #expect(setup.model.creationDraft == nil)
    #expect(!setup.model.isCreating)
    #expect(setup.fake.calls == [
      .fetchDevices, .create(displayName: "내 폰", image: .sample, profile: .smallPhone), .fetchDevices,
    ])
    let created = Self.list(setup.model)?.devices.first
    #expect(created?.displayName == "내 폰")
    #expect(setup.model.selection == Set([created?.id].compactMap(\.self)))
    #expect(setup.model.notices.isEmpty)
  }

  @Test("폴더블: 접기 설정이 있는 이미지로만 만들 수 있다")
  func foldableNeedsFoldSettings() async {
    let setup = await Self.loadedFixture(.emptySample)
    setup.model.createButtonTapped()
    setup.model.creationNameChanged("내 폴더블")
    setup.model.creationProfileChanged(.foldable)
    #expect(setup.model.creationDraft?.profile == .foldable)
    #expect(setup.model.creationDraft?.isProfileUnsupportedByImage == false)
    #expect(setup.model.creationDraft?.canSubmit == true)
    // 접기 설정이 없는 이미지로 바꿔도 받아 두고(고른 것을 바꾸지 않는다) 만들기만 막는다.
    setup.model.creationImageChanged(.olderSample)
    let unsupported = setup.model.creationDraft
    #expect(unsupported?.image == .olderSample)
    #expect(unsupported?.isProfileUnsupportedByImage == true)
    #expect(
      unsupported?.isProfileUnsupportedByImage
        == unsupported?.options.lacksFoldSettings(image: .olderSample, profile: .foldable)
    )
    #expect(unsupported?.canSubmit == false)
    await setup.model.creationConfirmTapped()
    #expect(setup.fake.calls == [.fetchDevices])
    #expect(setup.model.creationDraft == unsupported)
    setup.model.creationImageChanged(.sample)
    #expect(setup.model.creationDraft?.isProfileUnsupportedByImage == false)
    #expect(setup.model.creationDraft?.canSubmit == true)
    await setup.model.creationConfirmTapped()
    #expect(setup.fake.calls == [
      .fetchDevices, .create(displayName: "내 폴더블", image: .sample, profile: .foldable), .fetchDevices,
    ])
    let created = Self.list(setup.model)?.devices.first
    #expect(created?.formFactor == .foldable)
  }

  @Test("폴더블을 만들 수 있는 이미지가 하나도 없으면 초안이 그것을 알린다 (시트는 다른 이미지를 고르라는 안내 대신 다른 이유를 보인다)")
  func noFoldableImage() throws {
    let none = AndroidDeviceCreationOptions(
      installedImages: [.sample, .olderSample],
      foldableImages: [],
      host: .aarch64
    )
    var draft = try #require(AndroidDeviceCreationDraft(options: none))
    draft.profileChanged(.foldable)
    #expect(draft.isProfileUnsupportedByImage)
    #expect(!draft.hasFoldableImage)
    #expect(!draft.canSubmit)
    let some = try #require(AndroidDeviceCreationDraft(options: .sample))
    #expect(some.hasFoldableImage)
  }

  @Test("폴더블이 아니면 접기 설정이 없는 이미지여도 이유를 보이지 않는다")
  func nonFoldableIgnoresFoldSettings() async {
    let setup = await Self.loadedFixture()
    setup.model.createButtonTapped()
    #expect(setup.model.creationDraft?.profile == .phone)
    #expect(setup.model.creationDraft?.isProfileUnsupportedByImage == false)
    setup.model.creationImageChanged(.olderSample)
    #expect(setup.model.creationDraft?.image == .olderSample)
    #expect(setup.model.creationDraft?.isProfileUnsupportedByImage == false)
  }

  @Test("만드는 중에는 + 를 누를 수 없고 시트가 다시 열리지 않는다")
  func creatingBlocksCreate() async {
    let setup = await Self.loadedFixture { $0.suspendCreates() }
    setup.model.createButtonTapped()
    setup.model.creationNameChanged("폰")
    let create = Self.start { await setup.model.creationConfirmTapped() }
    await Self.waitUntil { setup.model.isCreating }
    #expect(setup.model.creationDraft == nil)
    #expect(!setup.model.canCreateDevice)
    setup.model.createButtonTapped()
    #expect(setup.model.creationDraft == nil)
    setup.fake.resumeCreates()
    await create.value()
    #expect(setup.model.canCreateDevice)
  }

  @Test(
    "만들지 못하면 입력한 이름과 이미지 API 로 알리고 다시 읽는다",
    arguments: [
      AndroidEmulatorError.nameUnavailable, .creationOptionUnavailable, .avdFolderUnavailable, .sdkUnavailable,
    ]
  )
  func createFailure(error: AndroidEmulatorError) async {
    let setup = await Self.loadedFixture { $0.setCreateError(error) }
    setup.model.createButtonTapped()
    setup.model.creationNameChanged("폰")
    await setup.model.creationConfirmTapped()
    #expect(Self.notices(setup.model) == [.createFailed(AndroidDeviceLabel(name: "폰", apiLabel: "37.0"), error)])
    #expect(Self.fetchCount(setup.fake) == 2)
    #expect(setup.model.selection.isEmpty)
  }

  @Test("이름에 문제가 있으면 만들지 않고 시트를 둔다")
  func invalidNameDoesNothing() async {
    let setup = await Self.loadedFixture()
    setup.model.createButtonTapped()
    await setup.model.creationConfirmTapped()
    #expect(setup.model.creationDraft != nil)
    #expect(setup.fake.calls == [.fetchDevices])
  }

  @Test("취소와 시트 닫기는 초안을 지운다")
  func cancelClearsDraft() async {
    let setup = await Self.loadedFixture()
    setup.model.createButtonTapped()
    setup.model.creationCancelTapped()
    #expect(setup.model.creationDraft == nil)
    setup.model.createButtonTapped()
    setup.model.creationSheetDismissed()
    #expect(setup.model.creationDraft == nil)
  }
}
