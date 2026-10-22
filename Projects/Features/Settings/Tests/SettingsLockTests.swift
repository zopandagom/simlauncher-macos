import Core
import DownloadInterface
import DownloadTesting
import PreferencesInterface
import PreferencesTesting
import Testing
@testable import SettingsFeature

/// 잠김(관리자 강제)일 때 Model 이 Preferences 쓰기와 받기를 부르지 않는지. Impl·Fake 도 `.locked` 로 막으므로
/// 결과가 아니라 호출 기록으로 Model 의 guard 를 따로 확인한다.
@MainActor
struct SettingsLockTests: SettingsModelTesting {
  static let first = "https://builds.example.com/ios/catalog.json"
  static let typed = "https://cdn.example.org/team/catalog.json"

  @Test("잠겼으면 canAdd·canEdit 가 false")
  func flags() {
    let model = Self.openedModel(preferences: PreferencesClientFake(urls: [Self.first], isLocked: true))
    model.catalogURLTextChanged(Self.typed)
    #expect(!model.canAdd)
    #expect(!model.canEdit)
  }

  @Test("잠긴 채 유효한 주소로 등록을 눌러도 받지 않고 addCatalogURL 을 부르지 않는다")
  func addIgnored() async {
    let preferences = PreferencesClientFake(urls: [Self.first], isLocked: true)
    let download = Self.catalogFake()
    let model = Self.openedModel(preferences: preferences, download: download)
    model.catalogURLTextChanged(Self.typed)

    await model.addButtonTapped()

    #expect(Self.fetchCount(download) == 0)
    #expect(Self.addCount(preferences) == 0)
    #expect(model.checkingURL == nil)
    #expect(model.result == nil)
  }

  @Test("잠겼으면 삭제를 눌러도 removeCatalogURL 을 부르지 않는다")
  func removeIgnored() {
    let preferences = PreferencesClientFake(urls: [Self.first], isLocked: true)
    let model = Self.openedModel(preferences: preferences)

    model.removeButtonTapped(Self.first)

    #expect(Self.removeCount(preferences) == 0)
    #expect(model.setting == CatalogURLSetting(urls: [Self.first], isLocked: true))
  }
}
