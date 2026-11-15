import PreferencesInterface
import PreferencesTesting
import Testing
@testable import SettingsFeature

/// "업데이트" 절: 새 버전 자동 확인 토글 (`AutomaticUpdateCheck`).
@MainActor
struct SettingsUpdateTests: SettingsModelTesting {
  /// `setAutomaticUpdateCheck` 호출 수.
  static func writeCount(_ preferences: PreferencesClientFake) -> Int {
    preferences.calls.filter {
      if case .setAutomaticUpdateCheck = $0 {
        true
      } else {
        false
      }
    }.count
  }

  @Test("창을 열면 자동 확인 설정과 잠금을 읽는다 (열기 전에는 기본값 켬)")
  func onAppearReads() {
    let preferences = PreferencesClientFake()
    preferences.setStoredAutomaticUpdateCheck(false, isLocked: true)
    let model = Self.makeModel(preferences: preferences)
    #expect(model.automaticUpdateCheck == .enabledDefault)

    model.onAppear()

    #expect(model.automaticUpdateCheck == AutomaticUpdateCheckSetting(isEnabled: false, isLocked: true))
  }

  @Test("토글을 끄고 켜면 저장하고 저장된 값을 다시 읽어 상태에 둔다")
  func toggleSaves() {
    let preferences = PreferencesClientFake()
    let model = Self.openedModel(preferences: preferences)

    model.automaticUpdateCheckChanged(false)

    #expect(preferences.storedAutomaticUpdateCheck == AutomaticUpdateCheckSetting(isEnabled: false, isLocked: false))
    #expect(model.automaticUpdateCheck == AutomaticUpdateCheckSetting(isEnabled: false, isLocked: false))

    model.automaticUpdateCheckChanged(true)

    #expect(preferences.storedAutomaticUpdateCheck == .enabledDefault)
    #expect(model.automaticUpdateCheck == .enabledDefault)
    #expect(Array(preferences.calls.suffix(2)) == [.setAutomaticUpdateCheck(true), .automaticUpdateCheck])
  }

  @Test("잠겼으면 토글 변경을 무시하고 쓰기를 부르지 않는다")
  func lockedIgnored() {
    let preferences = PreferencesClientFake()
    preferences.setStoredAutomaticUpdateCheck(true, isLocked: true)
    let model = Self.openedModel(preferences: preferences)

    model.automaticUpdateCheckChanged(false)

    #expect(Self.writeCount(preferences) == 0)
    #expect(model.automaticUpdateCheck == AutomaticUpdateCheckSetting(isEnabled: true, isLocked: true))
  }

  @Test("창을 연 뒤 관리자가 잠갔으면 쓰기가 실패하고 다시 읽어 잠금 상태(강제 값)로 바뀐다")
  func lockedAfterOpen() {
    let preferences = PreferencesClientFake()
    let model = Self.openedModel(preferences: preferences)
    preferences.setStoredAutomaticUpdateCheck(true, isLocked: true)

    model.automaticUpdateCheckChanged(false)

    #expect(Self.writeCount(preferences) == 1)
    #expect(model.automaticUpdateCheck == AutomaticUpdateCheckSetting(isEnabled: true, isLocked: true))
  }

  @Test("배포 저장소가 없는 빌드면 토글 변경을 무시하고 쓰기를 부르지 않는다")
  func unavailableIgnored() {
    let preferences = PreferencesClientFake()
    let model = Self.makeModel(preferences: preferences, isUpdateCheckAvailable: false)
    model.onAppear()

    model.automaticUpdateCheckChanged(false)

    #expect(!model.isUpdateCheckAvailable)
    #expect(Self.writeCount(preferences) == 0)
    #expect(preferences.storedAutomaticUpdateCheck == .enabledDefault)
  }
}
