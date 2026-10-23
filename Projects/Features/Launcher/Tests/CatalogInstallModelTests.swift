import Core
import DownloadInterface
import DownloadTesting
import Foundation
import PreferencesInterface
import PreferencesTesting
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

/// `CatalogInstallModel` 의 이벤트 메서드. 받기 겹침·취소는 `CatalogInstallLoadTests`.
@MainActor
struct CatalogInstallModelTests: CatalogInstallModelTesting {
  static let alphaKey = CatalogAppKey(sourceID: CatalogData.firstKey, appID: CatalogData.alpha)

  @Test("설치할 수 있는 기기(켜짐·꺼짐)에서 메뉴를 누르면 누른 시점의 기기로 열고, 설정을 한 번 읽어 카탈로그마다 한 번씩 받는다", arguments: [
    SampleID.iPhoneOn, SampleID.iPhoneOff,
  ])
  func menuOpensAndLoads(id: VirtualDevice.ID) async throws {
    let preferences = PreferencesClientFake(urls: [CatalogData.firstRaw, CatalogData.secondRaw])
    let download = CatalogData.fake()
    let (model, _) = Self.catalogModel(preferences: preferences, download: download)

    await model.menuTapped(Self.sampleDevice(id))

    #expect(model.draft?.deviceID == id)
    #expect(model.draft?.device == Self.label(id))
    #expect(preferences.calls == [.catalogURLs])
    let maxBytes = BuildCatalog.maxByteCount
    #expect(Set(download.calls) == [
      .fetchData(CatalogData.first.url, maxBytes: maxBytes), .fetchData(CatalogData.second.url, maxBytes: maxBytes),
    ])
    #expect(download.calls.count == 2)
    let catalog = try CatalogData.catalog(CatalogData.twoApps)
    #expect(Self.sourceStates(model) == [.loaded(catalog), .loaded(catalog)])
    #expect(model.draft?.isLoading == false)
  }

  @Test("쓸 수 없는·켜는 중인 기기와 이미 열린 동안(다른 기기 포함)에는 열지 않고 설정·받기도 부르지 않는다")
  func menuIgnored() async {
    let preferences = PreferencesClientFake(urls: [CatalogData.firstRaw])
    let download = CatalogData.fake()
    let (model, _) = Self.catalogModel(preferences: preferences, download: download)

    await model.menuTapped(Self.sampleDevice(SampleID.unavailableIPhone))
    await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOff, state: .booting))
    #expect(model.draft == nil)
    #expect(preferences.calls.isEmpty)
    #expect(download.calls.isEmpty)

    await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOn))
    await model.menuTapped(Self.sampleDevice(SampleID.iPadOff))
    #expect(model.draft?.deviceID == SampleID.iPhoneOn)
    #expect(preferences.calls == [.catalogURLs])
    #expect(download.calls.count == 1)
  }

  @Test("한 카탈로그가 받지 못해도(404) 다른 카탈로그는 앱 목록을 보이고, 구역은 저장 순서다")
  func oneCatalogFails() async throws {
    let download = CatalogData.fake()
    download.setFetchResult(.failure(.httpStatus(404)), for: CatalogData.first)
    let (model, _) = Self.catalogModel(download: download)

    await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOn))

    #expect(model.draft?.sources.map(\.id) == [CatalogData.firstKey, CatalogData.secondKey])
    let catalog = try CatalogData.catalog(CatalogData.twoApps)
    #expect(Self.sourceStates(model) == [.failed(.download(.httpStatus(404))), .loaded(catalog)])
  }

  @Test("형식에 맞지 않는 카탈로그는 그 구역만 형식 문제로 실패한다")
  func catalogProblem() async {
    let download = CatalogData.fake()
    download.setFetchResult(.success(CatalogData.newerSchema), for: CatalogData.first)
    download.setFetchResult(.success(CatalogData.html), for: CatalogData.second)
    let (model, _) = Self.catalogModel(download: download)

    await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOn))

    #expect(Self.sourceStates(model) == [
      .failed(.catalog(.unsupportedSchemaVersion(2))), .failed(.catalog(.notJSONObject)),
    ])
  }

  @Test("쓸 수 없는 주소와 같은 카탈로그의 두 번째 주소는 받지 않는다")
  func invalidAndDuplicateAreNotFetched() async {
    let urls = [CatalogData.firstRaw, CatalogData.httpRaw, CatalogData.firstDuplicateRaw, CatalogData.secondRaw]
    let download = CatalogData.fake()
    let (model, _) = Self.catalogModel(preferences: PreferencesClientFake(urls: urls), download: download)

    await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOn))

    #expect(Self.fetchedURLs(download).count == 2)
    #expect(Set(Self.fetchedURLs(download)) == [CatalogData.first.url, CatalogData.second.url])
    #expect(model.draft?.sources.map(\.raw) == [CatalogData.firstRaw, CatalogData.httpRaw, CatalogData.secondRaw])
  }

  @Test("등록한 카탈로그가 없으면 구역 없이 열고 받지 않는다. 잠긴 빈 목록도 같고 잠김을 알린다", arguments: [false, true])
  func emptySetting(isLocked: Bool) async {
    let download = CatalogData.fake()
    let preferences = PreferencesClientFake(urls: [], isLocked: isLocked)
    let (model, _) = Self.catalogModel(preferences: preferences, download: download)

    await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOn))

    #expect(model.draft?.isEmpty == true)
    #expect(model.draft?.isLocked == isLocked)
    #expect(model.draft?.showsOpenSettings == !isLocked)
    #expect(download.calls.isEmpty)
  }

  @Test("새로 고침은 설정을 다시 읽어 바깥에서 바뀐 목록으로 다시 받고, 닫힌 동안에는 아무것도 하지 않는다")
  func refreshRereadsSetting() async {
    let preferences = PreferencesClientFake(urls: [CatalogData.firstRaw])
    let download = CatalogData.fake()
    let (model, _) = Self.catalogModel(preferences: preferences, download: download)
    await model.refreshButtonTapped()
    #expect(preferences.calls.isEmpty)
    #expect(model.draft == nil)

    await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOn))
    preferences.setStored(urls: [CatalogData.firstRaw, CatalogData.secondRaw], isLocked: true)
    await model.refreshButtonTapped()

    #expect(preferences.calls == [.catalogURLs, .catalogURLs])
    #expect(model.draft?.sources.map(\.id) == [CatalogData.firstKey, CatalogData.secondKey])
    #expect(model.draft?.isLocked == true)
    #expect(Self.fetchedURLs(download).filter { $0 == CatalogData.first.url }.count == 2)
    #expect(Self.fetchedURLs(download).filter { $0 == CatalogData.second.url }.count == 1)
  }

  @Test("앱·버전 고르기는 시트 상태로 넘기고, 닫힌 동안에는 무시한다")
  func selectionEvents() async {
    let (model, _) = Self.catalogModel()
    model.appSelected(Self.alphaKey)
    model.versionSelected(CatalogData.alphaV1)
    #expect(model.draft == nil)

    await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOn))
    model.appSelected(Self.alphaKey)
    #expect(model.draft?.selectedApp == Self.alphaKey)
    #expect(model.draft?.selectedVersionID == CatalogData.alphaV2)
    model.versionSelected(CatalogData.alphaV1)
    #expect(model.draft?.selectedVersionID == CatalogData.alphaV1)
    model.appSelected(nil)
    #expect(model.draft?.selectedApp == nil)
  }

  @Test("취소·바깥 닫기는 시트를 닫고, 두 번 불려도 무해하다")
  func cancelAndDismiss() async {
    let (model, requests) = Self.catalogModel()
    await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOn))
    model.cancelTapped()
    #expect(model.draft == nil)
    model.cancelTapped()
    #expect(model.draft == nil)

    await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOff))
    #expect(model.draft?.deviceID == SampleID.iPhoneOff)
    model.sheetDismissed()
    model.sheetDismissed()
    #expect(model.draft == nil)
    #expect(requests.values.isEmpty)
  }

  @Test("고른 버전이 있으면 시트를 닫고 누른 시점의 기기와 그 버전의 빌드 주소로 설치를 한 번 요청한다")
  func installRequestsSelectedVersion() async {
    let (model, requests) = Self.catalogModel()
    await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOff))
    model.appSelected(Self.alphaKey)

    await model.installButtonTapped()

    #expect(model.draft == nil)
    #expect(requests.values == [
      CatalogInstallRequest(
        deviceID: SampleID.iPhoneOff,
        device: Self.label(SampleID.iPhoneOff),
        buildURL: CatalogData.alphaV2URL
      ),
    ])
  }

  @Test("고른 버전이 없으면(앱 없음·버전 없음·다시 읽는 중·닫힘) 설치를 요청하지 않고 시트를 그대로 둔다")
  func installIgnoredWithoutVersion() async {
    let preferences = PreferencesClientFake(urls: [CatalogData.firstRaw])
    let download = CatalogData.fake()
    let (model, requests) = Self.catalogModel(preferences: preferences, download: download)
    await model.installButtonTapped()

    await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOn))
    await model.installButtonTapped()
    #expect(model.draft != nil)

    download.setFetchResult(.success(CatalogData.alphaWithoutVersions))
    await model.refreshButtonTapped()
    model.appSelected(Self.alphaKey)
    await model.installButtonTapped()
    #expect(model.draft?.selectedApp == Self.alphaKey)

    // 고른 앱의 카탈로그를 다시 읽는 중이면 고른 버전이 없다.
    download.setFetchResult(.success(CatalogData.twoApps))
    await model.refreshButtonTapped()
    model.appSelected(Self.alphaKey)
    download.suspendFetches()
    let refresh = Self.start { await model.refreshButtonTapped() }
    await Self.waitUntil { download.suspendedFetchCount == 1 }
    await model.installButtonTapped()
    #expect(model.draft?.versionPane == .loading)
    #expect(requests.values.isEmpty)

    download.resumeFetches()
    await Self.waitUntil { refresh.isFinished }
    #expect(model.draft?.canInstall == true)
  }

  @Test("설치 요청이 끝나기 전에 다시 눌러도 요청은 한 번이다")
  func installTwice() async {
    let (model, requests) = Self.catalogModel()
    await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOn))
    model.appSelected(Self.alphaKey)
    requests.suspend()

    let first = Self.start { await model.installButtonTapped() }
    await Self.waitUntil { requests.values.count == 1 }
    let second = Self.start { await model.installButtonTapped() }
    await Self.waitUntil { second.isFinished }

    #expect(requests.values.count == 1)
    requests.resume()
    await Self.waitUntil { first.isFinished && second.isFinished }
  }

  @Test("지금 받기에서 cancelled 가 와도 그 구역은 읽는 중에 갇히지 않고 실패로 끝난다")
  func cancelledResultIsFailure() async {
    let download = CatalogData.fake()
    download.setFetchResult(.failure(.cancelled), for: CatalogData.first)
    let (model, _) = Self.catalogModel(
      preferences: PreferencesClientFake(urls: [CatalogData.firstRaw]),
      download: download
    )

    await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOn))

    #expect(Self.sourceStates(model) == [.failed(.download(.cancelled))])
    #expect(model.draft?.isLoading == false)
  }
}
