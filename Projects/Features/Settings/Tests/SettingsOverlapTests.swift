import Core
import DownloadInterface
import DownloadTesting
import Foundation
import PreferencesInterface
import PreferencesTesting
import Testing
@testable import SettingsFeature

/// 확인 중(받기·해석 await) 에 들어온 이벤트. 멈출 수 있는 등록은 `start` 로 띄우고 `waitUntil` 로 기다린다.
@MainActor
struct SettingsOverlapTests: SettingsModelTesting {
  static let first = "https://builds.example.com/ios/catalog.json"
  static let typed = "https://cdn.example.org/team/catalog.json"
  static let other = "https://other.example/catalog.json"

  /// 받기가 멈춘 채 확인 중인 등록.
  struct Checking {
    let model: SettingsModel
    let download: DownloadClientFake
    let add: TrackedTask
  }

  /// 받기를 멈춘 Fake 로 등록을 띄우고 받기가 멈출 때까지 기다린다.
  static func checking(preferences: PreferencesClientFake = PreferencesClientFake()) async -> Checking {
    let download = Self.catalogFake()
    download.suspendFetches()
    let model = Self.openedModel(preferences: preferences, download: download)
    model.catalogURLTextChanged(Self.typed)
    let add = Self.start { await model.addButtonTapped() }
    await Self.waitUntil { download.suspendedFetchCount == 1 }
    return Checking(model: model, download: download, add: add)
  }

  @Test("확인 중 다시 눌러도 받기는 한 번")
  func secondTapIgnored() async {
    let checking = await Self.checking()
    let (model, download, add) = (checking.model, checking.download, checking.add)

    let second = Self.start { await model.addButtonTapped() }
    await Self.waitUntil { second.isFinished }

    #expect(Self.fetchCount(download) == 1)
    #expect(model.checkingURL == Self.url(Self.typed))
    download.resumeFetches()
    await Self.waitUntil { add.isFinished }
    #expect(Self.fetchCount(download) == 1)
  }

  @Test("확인 중 글자 입력은 무시한다")
  func typingIgnored() async {
    let checking = await Self.checking()
    let (model, download, add) = (checking.model, checking.download, checking.add)

    model.catalogURLTextChanged("https://changed.example/c.json")

    #expect(model.draftText == Self.typed)
    download.resumeFetches()
    await Self.waitUntil { add.isFinished }
  }

  @Test("확인 중 취소하면 그 자리에서 확인 전으로 돌아가고, 받기는 cancelled 로 끝나며, 결과 줄 없이 글자를 남기고 저장하지 않는다")
  func cancelTapped() async {
    let preferences = PreferencesClientFake()
    let checking = await Self.checking(preferences: preferences)
    let (model, download, add) = (checking.model, checking.download, checking.add)

    model.cancelCheckTapped()

    #expect(model.checkingURL == nil)
    #expect(model.canAdd)
    await Self.waitUntil { add.isFinished }
    download.resumeFetches()
    await add.value()
    #expect(model.result == nil)
    #expect(model.draftText == Self.typed)
    #expect(Self.addCount(preferences) == 0)
    #expect(download.suspendedFetchCount == 0)
  }

  @Test("확인 중 창을 닫으면 확인을 취소하고 저장하지 않는다")
  func windowClosed() async {
    let preferences = PreferencesClientFake()
    let checking = await Self.checking(preferences: preferences)
    let (model, download, add) = (checking.model, checking.download, checking.add)

    model.windowClosed()

    #expect(model.checkingURL == nil)
    await Self.waitUntil { add.isFinished }
    download.resumeFetches()
    await add.value()
    #expect(model.result == nil)
    #expect(Self.addCount(preferences) == 0)
  }

  @Test("확인 중 창을 다시 열면 확인을 취소하고 최신 목록을 읽고 글자를 지운다")
  func reopenedDuringCheck() async {
    let preferences = PreferencesClientFake()
    let checking = await Self.checking(preferences: preferences)
    let (model, download, add) = (checking.model, checking.download, checking.add)
    preferences.setStored(urls: [Self.first], isLocked: false)

    model.onAppear()

    #expect(model.checkingURL == nil)
    #expect(model.draftText.isEmpty)
    #expect(model.setting.urls == [Self.first])
    await Self.waitUntil { add.isFinished }
    download.resumeFetches()
    await add.value()
    #expect(model.result == nil)
    #expect(Self.addCount(preferences) == 0)
  }

  @Test("확인 중 다른 항목을 지우면 바로 반영되고, 확인이 끝나면 지운 뒤 목록에 붙는다")
  func removeDuringCheck() async {
    let preferences = PreferencesClientFake(urls: [Self.first])
    let checking = await Self.checking(preferences: preferences)
    let (model, download, add) = (checking.model, checking.download, checking.add)

    model.removeButtonTapped(Self.first)
    #expect(model.setting.urls.isEmpty)
    #expect(model.checkingURL == Self.url(Self.typed))
    download.resumeFetches()
    await Self.waitUntil { add.isFinished }

    #expect(model.setting.urls == [Self.typed])
    #expect(model.result == .added(raw: Self.typed, appCount: 2))
  }

  // MARK: - 늦은 결과 (취소를 무시하고 돌아오는 받기)

  @Test("취소 뒤 받기가 성공으로 늦게 돌아오면 저장하지 않고 결과 줄도 없다")
  func lateSuccessDiscarded() async {
    let preferences = PreferencesClientFake()
    let download = LateFetchDownloadClient()
    let model = Self.openedModel(preferences: preferences, download: download)
    model.catalogURLTextChanged(Self.typed)
    let add = Self.start { await model.addButtonTapped() }
    await Self.waitUntil { download.fetchCount == 1 }

    model.cancelCheckTapped()
    download.release(call: 1, with: .success(CatalogData.twoApps))
    await Self.waitUntil { add.isFinished }

    #expect(Self.addCount(preferences) == 0)
    #expect(preferences.stored.urls.isEmpty)
    #expect(model.result == nil)
    #expect(model.checkingURL == nil)
    #expect(model.draftText == Self.typed)
  }

  @Test("취소 뒤 받기가 늦게 성공했는데 내용이 형식 문제면 결과 줄 없이 버린다")
  func lateCatalogProblemDiscarded() async {
    let preferences = PreferencesClientFake()
    let download = LateFetchDownloadClient()
    let model = Self.openedModel(preferences: preferences, download: download)
    model.catalogURLTextChanged(Self.typed)
    let add = Self.start { await model.addButtonTapped() }
    await Self.waitUntil { download.fetchCount == 1 }

    model.cancelCheckTapped()
    download.release(call: 1, with: .success(CatalogData.loginHTML))
    await Self.waitUntil { add.isFinished }

    #expect(model.result == nil)
    #expect(model.checkingURL == nil)
    #expect(Self.addCount(preferences) == 0)
  }

  @Test("취소 직후 다시 등록하면 두 번째만 반영된다: 첫 확인이 늦게 실패해도 두 번째 확인 중 상태가 남는다")
  func lateFailureAfterRetry() async {
    let preferences = PreferencesClientFake()
    let download = LateFetchDownloadClient()
    let model = Self.openedModel(preferences: preferences, download: download)
    model.catalogURLTextChanged(Self.typed)
    let first = Self.start { await model.addButtonTapped() }
    await Self.waitUntil { download.fetchCount == 1 }
    model.cancelCheckTapped()
    model.catalogURLTextChanged(Self.other)
    let second = Self.start { await model.addButtonTapped() }
    await Self.waitUntil { download.fetchCount == 2 }

    download.release(call: 1, with: .failure(.httpStatus(500)))
    await Self.waitUntil { first.isFinished }

    #expect(model.checkingURL == Self.url(Self.other))
    #expect(model.result == nil)
    #expect(!second.isFinished)

    download.release(call: 2, with: .success(CatalogData.twoApps))
    await Self.waitUntil { second.isFinished }
    #expect(model.result == .added(raw: Self.other, appCount: 2))
    #expect(preferences.stored.urls == [Self.other])
    #expect(model.checkingURL == nil)
  }

  @Test("취소 직후 다시 등록했는데 첫 확인이 늦게 성공하면 첫 주소는 저장하지 않고 두 번째만 저장한다")
  func lateSuccessAfterRetry() async {
    let preferences = PreferencesClientFake()
    let download = LateFetchDownloadClient()
    let model = Self.openedModel(preferences: preferences, download: download)
    model.catalogURLTextChanged(Self.typed)
    let first = Self.start { await model.addButtonTapped() }
    await Self.waitUntil { download.fetchCount == 1 }
    model.cancelCheckTapped()
    model.catalogURLTextChanged(Self.other)
    let second = Self.start { await model.addButtonTapped() }
    await Self.waitUntil { download.fetchCount == 2 }

    download.release(call: 1, with: .success(CatalogData.twoApps))
    await Self.waitUntil { first.isFinished }
    #expect(model.checkingURL == Self.url(Self.other))
    #expect(Self.addCount(preferences) == 0)

    download.release(call: 2, with: .success(CatalogData.twoApps))
    await Self.waitUntil { second.isFinished }
    #expect(preferences.stored.urls == [Self.other])
  }
}
