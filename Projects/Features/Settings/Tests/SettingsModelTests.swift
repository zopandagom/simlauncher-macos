import Core
import DownloadInterface
import DownloadTesting
import PreferencesInterface
import PreferencesTesting
import Testing
@testable import SettingsFeature

@MainActor
struct SettingsModelTests: SettingsModelTesting {
  static let first = "https://builds.example.com/ios/catalog.json"
  static let second = "https://cdn.example.org/team/catalog.json"

  // MARK: - 창 열기

  @Test("만들 때는 아무것도 읽지 않고, 창을 열면 목록과 잠금을 읽는다")
  func onAppearReads() {
    let preferences = PreferencesClientFake(urls: [Self.first], isLocked: true)
    let model = SettingsModel(preferences: preferences, download: DownloadClientFake())
    #expect(preferences.calls.isEmpty)
    #expect(model.setting == .empty)

    model.onAppear()

    #expect(preferences.calls == [.catalogURLs])
    #expect(model.setting == CatalogURLSetting(urls: [Self.first], isLocked: true))
  }

  @Test("다시 열면 최신 목록을 읽고 입력과 결과 줄을 지운다")
  func reopenClears() async {
    let preferences = PreferencesClientFake()
    let model = Self.openedModel(preferences: preferences)
    model.catalogURLTextChanged(Self.first)
    await model.addButtonTapped()
    #expect(model.result != nil)
    model.catalogURLTextChanged("https://typing.example/")
    model.windowClosed()
    preferences.setStored(urls: [Self.first, Self.second], isLocked: false)

    model.onAppear()

    #expect(model.setting.urls == [Self.first, Self.second])
    #expect(model.draftText.isEmpty)
    #expect(model.result == nil)
    #expect(model.checkingURL == nil)
  }

  @Test("entries 는 Core 규칙의 결과와 같다")
  func entries() {
    let model = Self.openedModel(preferences: PreferencesClientFake(urls: CatalogURLSetting.withProblems.urls))
    #expect(model.entries == CatalogURLList.entries(CatalogURLSetting.withProblems.urls))
  }

  // MARK: - 입력

  @Test("입력을 바꾸면 글자를 바꾸고 결과 줄을 지운다")
  func textChangedClearsResult() async {
    let model = Self.openedModel()
    model.catalogURLTextChanged(Self.first)
    await model.addButtonTapped()
    #expect(model.result != nil)

    model.catalogURLTextChanged("h")

    #expect(model.draftText == "h")
    #expect(model.result == nil)
  }

  @Test(
    "입력 문제 안내: 빈 입력은 nil, 주소 검사 문제는 그 문제",
    arguments: [
      ("", nil),
      ("   ", nil),
      ("http://example.com/catalog.json", CatalogDraftProblem.url(.notHTTPS)),
      ("https://user:pw@example.com/catalog.json", .url(.hasCredentials)),
      ("https://exa mple.com/c.json", .url(.malformed)),
      ("https://", .url(.missingHost)),
      ("https://example.com/catalog.json", nil),
    ] as [(String, CatalogDraftProblem?)]
  )
  func draftProblem(text: String, expected: CatalogDraftProblem?) {
    let model = Self.openedModel()
    model.catalogURLTextChanged(text)
    #expect(model.draftProblem == expected)
  }

  @Test(
    "표기가 달라도 같은 카탈로그가 등록돼 있으면 duplicate",
    arguments: [
      "https://builds.example.com/ios/catalog.json",
      "HTTPS://BUILDS.EXAMPLE.COM:443/ios/catalog.json#x",
      " https://builds.example.com/ios/./catalog.json ",
    ]
  )
  func draftDuplicate(text: String) {
    let model = Self.openedModel(preferences: PreferencesClientFake(urls: [Self.first]))
    model.catalogURLTextChanged(text)
    #expect(model.draftProblem == .duplicate)
    #expect(!model.canAdd)
  }

  @Test("canAdd: 잠기지 않고, 확인 중이 아니고, 통과한 주소이고, 중복이 아닐 때만")
  func canAdd() {
    let model = Self.openedModel(preferences: PreferencesClientFake(urls: [Self.first]))
    #expect(!model.canAdd)
    model.catalogURLTextChanged("http://example.com/c.json")
    #expect(!model.canAdd)
    model.catalogURLTextChanged(Self.first)
    #expect(!model.canAdd)
    model.catalogURLTextChanged(Self.second)
    #expect(model.canAdd)
    #expect(model.canEdit)
  }

  @Test("중복이면 눌러도 받지 않고 저장하지 않는다")
  func duplicateDoesNotFetch() async {
    let preferences = PreferencesClientFake(urls: [Self.first])
    let download = Self.catalogFake()
    let model = Self.openedModel(preferences: preferences, download: download)
    model.catalogURLTextChanged("HTTPS://builds.example.com/ios/catalog.json")

    await model.addButtonTapped()

    #expect(Self.fetchCount(download) == 0)
    #expect(Self.addCount(preferences) == 0)
    #expect(model.checkingURL == nil)
    #expect(model.result == nil)
  }

  @Test("빈 입력·주소 문제면 눌러도 받지 않는다")
  func invalidDoesNotFetch() async {
    let download = Self.catalogFake()
    let model = Self.openedModel(download: download)

    await model.addButtonTapped()
    model.catalogURLTextChanged("http://example.com/c.json")
    await model.addButtonTapped()

    #expect(Self.fetchCount(download) == 0)
  }

  // MARK: - 삭제

  @Test("삭제는 저장 문자열로 지우고 돌려받은 목록을 보이며 결과 줄을 지운다")
  func remove() async {
    let preferences = PreferencesClientFake(urls: [Self.first])
    let model = Self.openedModel(preferences: preferences)
    model.catalogURLTextChanged(Self.second)
    await model.addButtonTapped()
    #expect(model.result != nil)

    model.removeButtonTapped(Self.first)

    #expect(model.setting.urls == [Self.second])
    #expect(model.result == nil)
    #expect(preferences.calls.last == .removeCatalogURL(Self.first))
  }

  @Test("없는 항목을 지우면 목록이 그대로다")
  func removeMissing() {
    let model = Self.openedModel(preferences: PreferencesClientFake(urls: [Self.first]))
    model.removeButtonTapped(Self.second)
    #expect(model.setting.urls == [Self.first])
  }

  @Test("창을 연 뒤 관리자가 잠갔으면 삭제는 locked 로 끝나고 다시 읽어 잠금 표시로 바뀐다")
  func removeAfterOutsideLock() {
    let preferences = PreferencesClientFake(urls: [Self.first])
    let model = Self.openedModel(preferences: preferences)
    preferences.setStored(urls: [Self.first, Self.second], isLocked: true)

    model.removeButtonTapped(Self.first)

    #expect(model.setting == CatalogURLSetting(urls: [Self.first, Self.second], isLocked: true))
    #expect(!model.canEdit)
    #expect(preferences.calls.suffix(2) == [.removeCatalogURL(Self.first), .catalogURLs])
  }

  @Test("창을 연 뒤 바깥에서 더한 값은 삭제 뒤 목록에 보인다 (최신 값에서 뺀다)")
  func removeShowsOutsideChange() {
    let preferences = PreferencesClientFake(urls: [Self.first])
    let model = Self.openedModel(preferences: preferences)
    preferences.setStored(urls: [Self.first, Self.second], isLocked: false)

    model.removeButtonTapped(Self.first)

    #expect(model.setting.urls == [Self.second])
  }

  @Test("확인 중이 아닐 때 취소는 아무것도 바꾸지 않는다")
  func cancelWithoutCheck() {
    let model = Self.openedModel()
    model.catalogURLTextChanged(Self.first)
    model.cancelCheckTapped()
    #expect(model.draftText == Self.first)
    #expect(model.checkingURL == nil)
  }
}
