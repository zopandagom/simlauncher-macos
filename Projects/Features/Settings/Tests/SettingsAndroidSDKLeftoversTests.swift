import AndroidSDKInterface
import AndroidSDKTesting
import Core
import Foundation
import PreferencesInterface
import PreferencesTesting
import Testing
@testable import SettingsFeature

/// "Android SDK 위치" 절: 위치가 바뀌면 바뀜 알림 뒤 이전 위치의 남은 스테이징을 지운다 (`removeLeftovers(in:)`).
@MainActor
struct SettingsAndroidSDKLeftoversTests: SettingsAndroidSDKTesting {
  /// 바뀜 알림 때 이미 기록된 이전 위치 정리 수 (알림마다 하나).
  final class CleanupsAtChange {
    var counts: [Int] = []
  }

  static func openedModel(
    preferences: PreferencesClientFake,
    androidSDK: AndroidSDKClientFake,
    cleanups: CleanupsAtChange
  ) -> SettingsModel {
    let model = SettingsModel(
      preferences: preferences, download: Self.catalogFake(), androidSDK: androidSDK, home: testHome,
      androidSDKLocationChanged: { cleanups.counts.append(Self.cleanedRoots(androidSDK).count) }
    )
    model.onAppear()
    return model
  }

  /// `removeLeftovers(in:)` 로 넘긴 위치들.
  static func cleanedRoots(_ androidSDK: AndroidSDKClientFake) -> [AndroidSDKRoot] {
    androidSDK.calls.compactMap {
      if case let .removeLeftoversIn(root) = $0 {
        root
      } else {
        nil
      }
    }
  }

  static func root(_ path: String) throws -> AndroidSDKRoot {
    guard case let .root(root) = AndroidSDKRootChoice.resolve(.path(path), home: testHome) else {
      throw CancellationError()
    }
    return root
  }

  @Test("폴더를 골라 위치가 바뀌면 알린 뒤 이전 위치를 정리한다 (지금 위치 정리·받기 폴더 정리는 부르지 않는다)")
  func chooseCleansPrevious() async throws {
    let preferences = PreferencesClientFake(androidSDKPath: Self.stored("/Volumes/Old/sdk"))
    let androidSDK = AndroidSDKClientFake()
    androidSDK.setCandidateResult((.sdk, true))
    let cleanups = CleanupsAtChange()
    let model = Self.openedModel(preferences: preferences, androidSDK: androidSDK, cleanups: cleanups)

    await model.sdkFolderChosen(Self.chosen)

    #expect(try Self.cleanedRoots(androidSDK) == [Self.root("/Volumes/Old/sdk")])
    #expect(cleanups.counts == [0])
    #expect(!androidSDK.calls.contains(.removeLeftovers))
  }

  @Test("기본 위치에서 다른 폴더를 고르면 기본 위치를 정리한다")
  func chooseFromDefaultCleansDefault() async {
    let androidSDK = AndroidSDKClientFake()
    androidSDK.setCandidateResult((.empty, true))
    let cleanups = CleanupsAtChange()
    let model = Self.openedModel(preferences: PreferencesClientFake(), androidSDK: androidSDK, cleanups: cleanups)

    await model.sdkFolderChosen(Self.chosen)

    #expect(Self.cleanedRoots(androidSDK) == [AndroidSDKRoot(url: Self.defaultURL, isDefault: true)])
    #expect(cleanups.counts == [0])
  }

  @Test("기본 위치로 되돌리면 알린 뒤 이전 위치를 정리한다")
  func resetCleansPrevious() async throws {
    let preferences = PreferencesClientFake(androidSDKPath: Self.stored("/Volumes/Old/sdk"))
    let androidSDK = AndroidSDKClientFake()
    let cleanups = CleanupsAtChange()
    let model = Self.openedModel(preferences: preferences, androidSDK: androidSDK, cleanups: cleanups)

    await model.sdkDefaultButtonTapped()

    #expect(try Self.cleanedRoots(androidSDK) == [Self.root("/Volumes/Old/sdk")])
    #expect(cleanups.counts == [0])
  }

  @Test("같은 위치를 다시 고르면 정리하지 않는다")
  func sameLocationNoCleanup() async {
    let preferences = PreferencesClientFake(androidSDKPath: Self.stored(Self.chosenPath))
    let androidSDK = AndroidSDKClientFake()
    androidSDK.setCandidateResult((.sdk, true))
    let cleanups = CleanupsAtChange()
    let model = Self.openedModel(preferences: preferences, androidSDK: androidSDK, cleanups: cleanups)

    await model.sdkFolderChosen(Self.chosen)

    #expect(Self.cleanedRoots(androidSDK).isEmpty)
    #expect(cleanups.counts.isEmpty)
  }

  @Test("바깥에서 같은 값으로 잠겨 저장하지 못하고 위치가 그대로면 정리하지 않는다")
  func lockedUnchangedNoCleanup() async {
    let preferences = PreferencesClientFake(androidSDKPath: Self.stored("/Volumes/Old/sdk"))
    let androidSDK = AndroidSDKClientFake()
    let cleanups = CleanupsAtChange()
    let model = Self.openedModel(preferences: preferences, androidSDK: androidSDK, cleanups: cleanups)
    preferences.setStoredAndroidSDKPath(Self.stored("/Volumes/Old/sdk", isLocked: true))

    await model.sdkDefaultButtonTapped()

    #expect(Self.cleanedRoots(androidSDK).isEmpty)
    #expect(cleanups.counts.isEmpty)
  }

  @Test("이전 값이 잘못된 설정이면 알리기만 하고 정리하지 않는다")
  func invalidPreviousNoCleanup() async {
    let preferences = PreferencesClientFake(androidSDKPath: AndroidSDKPathSetting(value: .malformed, isLocked: false))
    let androidSDK = AndroidSDKClientFake()
    let cleanups = CleanupsAtChange()
    let model = Self.openedModel(preferences: preferences, androidSDK: androidSDK, cleanups: cleanups)

    await model.sdkDefaultButtonTapped()

    #expect(Self.cleanedRoots(androidSDK).isEmpty)
    #expect(cleanups.counts == [0])
  }
}
