import AndroidSDKInterface
import AndroidSDKTesting
import Core
import Foundation
import PreferencesInterface
import PreferencesTesting
import Testing
@testable import SettingsFeature

/// "Android SDK 위치" 절: 잠금·판정 중 겹침·기본 위치로 되돌리기.
@MainActor
struct SettingsAndroidSDKGuardTests: SettingsAndroidSDKTesting {
  // MARK: - 잠금

  @Test("잠겼으면 고르기·되돌리기를 무시한다 (판정·쓰기 없음)")
  func lockedIgnored() async {
    let preferences = PreferencesClientFake(androidSDKPath: Self.stored(Self.chosenPath, isLocked: true))
    let androidSDK = AndroidSDKClientFake()
    let changes = LocationChangeCounter()
    let model = Self.openedModel(preferences: preferences, androidSDK: androidSDK, locationChanges: changes)
    #expect(!model.canChooseSDKFolder)
    #expect(!model.canResetSDKFolder)

    await model.sdkFolderChosen(Self.other)
    model.sdkDefaultButtonTapped()

    #expect(Self.inspectCount(androidSDK) == 0)
    #expect(Self.sdkWriteCount(preferences) == 0)
    #expect(model.androidSDKCandidate == nil)
    #expect(changes.isEmpty)
  }

  @Test("판정 중 바깥에서 잠기면 저장하지 못하고, 다시 읽어 잠금 안내로 바꾸며 결과 줄을 남기지 않는다")
  func lockedDuringInspection() async {
    let preferences = PreferencesClientFake()
    let androidSDK = AndroidSDKClientFake()
    androidSDK.suspendInspections()
    let changes = LocationChangeCounter()
    let model = Self.openedModel(preferences: preferences, androidSDK: androidSDK, locationChanges: changes)

    let task = Self.start { await model.sdkFolderChosen(Self.chosen) }
    await Self.waitUntil { androidSDK.suspendedInspectionCount == 1 }
    preferences.setStoredAndroidSDKPath(AndroidSDKPathSetting(value: .absent, isLocked: true))
    androidSDK.resumeInspections()
    await task.value()

    #expect(Self.sdkWrites(preferences) == [Self.chosenPath])
    #expect(preferences.storedAndroidSDKPath == AndroidSDKPathSetting(value: .absent, isLocked: true))
    #expect(model.androidSDKPath.isLocked)
    #expect(model.androidSDKCandidate == nil)
    #expect(!model.isInspectingSDKFolder)
    #expect(changes.isEmpty)
  }

  // MARK: - 겹침

  @Test("판정 중 다시 고르기·되돌리기는 무시한다")
  func reentryGuard() async {
    let preferences = PreferencesClientFake(androidSDKPath: Self.stored("/Volumes/Old/sdk"))
    let androidSDK = AndroidSDKClientFake()
    androidSDK.suspendInspections()
    let model = Self.openedModel(preferences: preferences, androidSDK: androidSDK)

    let task = Self.start { await model.sdkFolderChosen(Self.chosen) }
    await Self.waitUntil { androidSDK.suspendedInspectionCount == 1 }
    #expect(!model.canChooseSDKFolder)
    #expect(!model.canResetSDKFolder)
    await model.sdkFolderChosen(Self.other)
    model.sdkDefaultButtonTapped()
    androidSDK.resumeInspections()
    await task.value()

    #expect(androidSDK.calls == [.inspectCandidateFolder(Self.chosen)])
    #expect(Self.sdkWrites(preferences) == [Self.chosenPath])
  }

  @Test("판정 중 창을 닫으면 늦게 끝난 판정은 저장하지 않고 결과 줄도 남기지 않는다")
  func windowClosedDropsInspection() async {
    let preferences = PreferencesClientFake()
    let androidSDK = AndroidSDKClientFake()
    androidSDK.suspendInspections()
    let changes = LocationChangeCounter()
    let model = Self.openedModel(preferences: preferences, androidSDK: androidSDK, locationChanges: changes)

    let task = Self.start { await model.sdkFolderChosen(Self.chosen) }
    await Self.waitUntil { androidSDK.suspendedInspectionCount == 1 }
    model.windowClosed()
    #expect(!model.isInspectingSDKFolder)
    androidSDK.resumeInspections()
    await task.value()

    #expect(Self.sdkWriteCount(preferences) == 0)
    #expect(model.androidSDKCandidate == nil)
    #expect(changes.isEmpty)
  }

  @Test("판정 중 창을 닫았다 다시 열면 새 창에서 바로 고를 수 있고, 앞 판정은 버린다")
  func reopenDuringInspection() async {
    let preferences = PreferencesClientFake()
    let androidSDK = AndroidSDKClientFake()
    androidSDK.suspendInspections()
    let model = Self.openedModel(preferences: preferences, androidSDK: androidSDK)

    let first = Self.start { await model.sdkFolderChosen(Self.chosen) }
    await Self.waitUntil { androidSDK.suspendedInspectionCount == 1 }
    model.windowClosed()
    model.onAppear()
    #expect(model.canChooseSDKFolder)
    let second = Self.start { await model.sdkFolderChosen(Self.other) }
    await Self.waitUntil { androidSDK.suspendedInspectionCount == 2 }
    androidSDK.resumeInspections()
    await first.value()
    await second.value()

    #expect(Self.sdkWrites(preferences) == [Self.other.path(percentEncoded: false)])
  }

  // MARK: - 기본 위치로 되돌리기

  @Test("고른 위치에서 되돌리면 키를 지우고 알리며 결과 줄을 지운다")
  func resetToDefault() async {
    let preferences = PreferencesClientFake(androidSDKPath: Self.stored("/Volumes/Old/sdk"))
    let androidSDK = AndroidSDKClientFake()
    androidSDK.setCandidateResult((.otherContents, true))
    let changes = LocationChangeCounter()
    let model = Self.openedModel(preferences: preferences, androidSDK: androidSDK, locationChanges: changes)
    await model.sdkFolderChosen(Self.other)
    #expect(model.androidSDKCandidate != nil)

    model.sdkDefaultButtonTapped()

    #expect(Self.sdkWrites(preferences) == [nil])
    #expect(model.androidSDKPath == .absent)
    #expect(model.androidSDKCandidate == nil)
    #expect(!model.canResetSDKFolder)
    #expect(changes.count == 1)
  }

  @Test("잘못된 저장 값도 되돌릴 수 있다")
  func resetInvalidSetting() {
    let preferences = PreferencesClientFake(androidSDKPath: AndroidSDKPathSetting(value: .malformed, isLocked: false))
    let changes = LocationChangeCounter()
    let model = Self.openedModel(preferences: preferences, locationChanges: changes)

    model.sdkDefaultButtonTapped()

    #expect(Self.sdkWrites(preferences) == [nil])
    #expect(model.androidSDKRootChoice == .root(AndroidSDKRoot(url: Self.defaultURL, isDefault: true)))
    #expect(changes.count == 1)
  }

  @Test("이미 기본 위치면 되돌리기를 무시한다")
  func resetIgnoredWhenDefault() {
    let preferences = PreferencesClientFake()
    let changes = LocationChangeCounter()
    let model = Self.openedModel(preferences: preferences, locationChanges: changes)

    model.sdkDefaultButtonTapped()

    #expect(Self.sdkWriteCount(preferences) == 0)
    #expect(changes.isEmpty)
  }

  @Test("창을 연 뒤 바깥에서 잠긴 채 되돌리면 쓰지 못하고 다시 읽어 잠금 안내로 바꾼다")
  func resetLockedOutside() {
    let preferences = PreferencesClientFake(androidSDKPath: Self.stored("/Volumes/Old/sdk"))
    let changes = LocationChangeCounter()
    let model = Self.openedModel(preferences: preferences, locationChanges: changes)
    preferences.setStoredAndroidSDKPath(Self.stored("/Volumes/Old/sdk", isLocked: true))

    model.sdkDefaultButtonTapped()

    #expect(Self.sdkWrites(preferences) == [nil])
    #expect(model.androidSDKPath == Self.stored("/Volumes/Old/sdk", isLocked: true))
    #expect(changes.isEmpty)
  }
}
