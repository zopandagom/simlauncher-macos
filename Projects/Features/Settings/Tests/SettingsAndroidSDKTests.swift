import AndroidSDKInterface
import AndroidSDKTesting
import Core
import Foundation
import PreferencesInterface
import PreferencesTesting
import Testing
@testable import SettingsFeature

/// "Android SDK 위치" 절: 창 열기·폴더 고르기와 위치 바뀜 알림.
@MainActor
struct SettingsAndroidSDKTests: SettingsAndroidSDKTesting {
  // MARK: - 창 열기

  @Test("창을 열면 SDK 위치를 읽고, 키가 없으면 기본 위치다")
  func onAppearReadsDefault() {
    let model = Self.openedModel()

    #expect(model.androidSDKPath == .absent)
    #expect(model.androidSDKRootChoice == .root(AndroidSDKRoot(url: Self.defaultURL, isDefault: true)))
    #expect(model.canChooseSDKFolder)
    #expect(!model.canResetSDKFolder)
  }

  @Test("창을 열면 고른 위치를 읽고, 기본이 아니면 되돌릴 수 있다")
  func onAppearReadsChosen() {
    let preferences = PreferencesClientFake(androidSDKPath: Self.stored(Self.chosenPath))
    let model = Self.openedModel(preferences: preferences)

    guard case let .root(root) = model.androidSDKRootChoice else {
      Issue.record("위치로 풀리지 않았다")
      return
    }
    #expect(!root.isDefault)
    #expect(root.url.path(percentEncoded: false) == Self.chosenPath)
    #expect(model.canResetSDKFolder)
  }

  @Test("저장 값을 경로로 읽을 수 없으면 invalidSetting 이고, 잠기지 않았으면 되돌릴 수 있다")
  func invalidSetting() {
    for value in [AndroidSDKPathSetting.Value.malformed, .path("relative/sdk"), .path("")] {
      let preferences = PreferencesClientFake(androidSDKPath: AndroidSDKPathSetting(value: value, isLocked: false))
      let model = Self.openedModel(preferences: preferences)
      #expect(model.androidSDKRootChoice == .invalidSetting, "\(value)")
      #expect(model.canResetSDKFolder, "\(value)")
    }
  }

  @Test("다시 열면 바깥에서 바뀐 위치를 읽고 결과 줄을 지운다")
  func reopenReadsLatest() async {
    let preferences = PreferencesClientFake()
    let model = Self.openedModel(preferences: preferences)
    await model.sdkFolderChosen(Self.chosen)
    #expect(model.androidSDKCandidate != nil)
    model.windowClosed()
    preferences.setStoredAndroidSDKPath(Self.stored("/Volumes/Other/sdk"))

    model.onAppear()

    #expect(model.androidSDKPath == Self.stored("/Volumes/Other/sdk"))
    #expect(model.androidSDKCandidate == nil)
  }

  // MARK: - 폴더 고르기

  @Test("빈 폴더(쓸 수 있음)를 고르면 저장하고 결과 줄을 두고 한 번 알린다")
  func chooseEmptySaves() async {
    let preferences = PreferencesClientFake()
    let androidSDK = AndroidSDKClientFake()
    androidSDK.setCandidateResult((.empty, true), for: Self.chosen)
    let changes = LocationChangeCounter()
    let model = Self.openedModel(preferences: preferences, androidSDK: androidSDK, locationChanges: changes)

    await model.sdkFolderChosen(Self.chosen)

    #expect(androidSDK.calls == [.inspectCandidateFolder(Self.chosen)])
    #expect(Self.sdkWrites(preferences) == [Self.chosenPath])
    #expect(model.androidSDKPath == Self.stored(Self.chosenPath))
    #expect(model.androidSDKCandidate == SettingsSDKFolderResult(
      path: Self.chosenPath,
      candidate: .empty,
      writable: true
    ))
    #expect(model.androidSDKCandidate?.isSaved == true)
    #expect(!model.isInspectingSDKFolder)
    #expect(changes.count == 1)
  }

  @Test("쓸 수 없는 SDK 폴더도 저장한다 (있는 도구는 쓴다)")
  func chooseReadOnlySDKSaves() async {
    let preferences = PreferencesClientFake()
    let androidSDK = AndroidSDKClientFake()
    androidSDK.setCandidateResult((.sdk, false))
    let changes = LocationChangeCounter()
    let model = Self.openedModel(preferences: preferences, androidSDK: androidSDK, locationChanges: changes)

    await model.sdkFolderChosen(Self.chosen)

    #expect(Self.sdkWrites(preferences) == [Self.chosenPath])
    #expect(model.androidSDKCandidate == SettingsSDKFolderResult(
      path: Self.chosenPath,
      candidate: .sdk,
      writable: false
    ))
    #expect(changes.count == 1)
  }

  @Test(
    "빈 폴더(쓸 수 없음)·다른 내용·폴더 아님·없음·읽기 실패·링크 미지원 볼륨은 저장하지 않고 이유를 둔다",
    arguments: [
      (AndroidSDKFolderCandidate.empty, false), (.otherContents, true), (.notDirectory, true), (.missing, true),
      (.unreadable, true), (.unsupportedVolume, true),
    ] as [(AndroidSDKFolderCandidate, Bool)]
  )
  func chooseRejected(candidate: AndroidSDKFolderCandidate, writable: Bool) async {
    let preferences = PreferencesClientFake(androidSDKPath: Self.stored("/Volumes/Old/sdk"))
    let androidSDK = AndroidSDKClientFake()
    androidSDK.setCandidateResult((candidate, writable))
    let changes = LocationChangeCounter()
    let model = Self.openedModel(preferences: preferences, androidSDK: androidSDK, locationChanges: changes)

    await model.sdkFolderChosen(Self.other)

    #expect(Self.sdkWriteCount(preferences) == 0)
    #expect(model.androidSDKPath == Self.stored("/Volumes/Old/sdk"))
    let path = Self.other.path(percentEncoded: false)
    #expect(model.androidSDKCandidate == SettingsSDKFolderResult(path: path, candidate: candidate, writable: writable))
    #expect(model.androidSDKCandidate?.isSaved == false)
    #expect(changes.isEmpty)
  }

  @Test("기본 위치와 같은 폴더를 고르면 키를 지우고, 바뀌었을 때만 알린다")
  func chooseDefaultClearsKey() async {
    let preferences = PreferencesClientFake(androidSDKPath: Self.stored(Self.chosenPath))
    let androidSDK = AndroidSDKClientFake()
    androidSDK.setCandidateResult((.sdk, true))
    let changes = LocationChangeCounter()
    let model = Self.openedModel(preferences: preferences, androidSDK: androidSDK, locationChanges: changes)

    await model.sdkFolderChosen(Self.defaultURL)

    #expect(Self.sdkWrites(preferences) == [nil])
    #expect(model.androidSDKPath == .absent)
    #expect(changes.count == 1)

    // 이미 기본 위치일 때 다시 기본 위치를 고르면 알리지 않는다.
    await model.sdkFolderChosen(Self.defaultURL)

    #expect(Self.sdkWrites(preferences) == [nil, nil])
    #expect(changes.count == 1)
  }

  @Test("지금 위치와 같은 폴더를 다시 고르면 저장은 하되 알리지 않는다")
  func chooseSameDoesNotNotify() async {
    let preferences = PreferencesClientFake(androidSDKPath: Self.stored(Self.chosenPath))
    let changes = LocationChangeCounter()
    let model = Self.openedModel(preferences: preferences, locationChanges: changes)

    await model.sdkFolderChosen(Self.chosen)

    #expect(Self.sdkWrites(preferences) == [Self.chosenPath])
    #expect(model.androidSDKCandidate?.isSaved == true)
    #expect(changes.isEmpty)
  }

  @Test("창을 연 뒤 바깥에서 위치가 바뀌었으면, 창이 읽은 값과 같은 폴더를 골라도 알린다")
  func outsideChangeThenChooseNotifies() async {
    let preferences = PreferencesClientFake(androidSDKPath: Self.stored(Self.chosenPath))
    let changes = LocationChangeCounter()
    let model = Self.openedModel(preferences: preferences, locationChanges: changes)
    preferences.setStoredAndroidSDKPath(Self.stored("/Volumes/Other/sdk"))

    await model.sdkFolderChosen(Self.chosen)

    #expect(model.androidSDKPath == Self.stored(Self.chosenPath))
    #expect(changes.count == 1)
  }

  @Test("새로 고르면 앞 결과 줄을 지운다")
  func newChoiceClearsResult() async {
    let androidSDK = AndroidSDKClientFake()
    androidSDK.setCandidateResult((.otherContents, true))
    let model = Self.openedModel(androidSDK: androidSDK)
    await model.sdkFolderChosen(Self.other)
    #expect(model.androidSDKCandidate != nil)
    androidSDK.suspendInspections()

    let task = Self.start { await model.sdkFolderChosen(Self.chosen) }
    await Self.waitUntil { androidSDK.suspendedInspectionCount == 1 }

    #expect(model.androidSDKCandidate == nil)
    #expect(model.isInspectingSDKFolder)
    androidSDK.resumeInspections()
    await task.value()
  }
}
