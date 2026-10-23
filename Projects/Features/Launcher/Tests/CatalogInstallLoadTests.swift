import Core
import DownloadInterface
import DownloadTesting
import Foundation
import PreferencesTesting
import SimulatorTesting
import Synchronization
import Testing
@testable import LauncherFeature

/// 카탈로그 받기의 겹침·취소: 결과는 오는 대로, 새로 고침·닫기 뒤의 옛 결과는 버린다. 멈춘 받기·늦은 받기는 직접 await 하지
/// 않고 `start`·`waitUntil` 로 기다리고, 테스트 끝에 재개해 남은 작업이 끝나기를 기다린다.
@MainActor
struct CatalogInstallLoadTests: CatalogInstallModelTesting {
  static let alphaKey = CatalogAppKey(sourceID: CatalogData.firstKey, appID: CatalogData.alpha)

  @Test("결과는 끝난 카탈로그부터 보이고, 구역 순서는 저장 순서 그대로다")
  func resultsArriveAsTheyFinish() async throws {
    let download = CatalogData.fake()
    download.suspendFetches(for: CatalogData.first)
    let (model, _) = Self.catalogModel(download: download)
    let catalog = try CatalogData.catalog(CatalogData.twoApps)

    let open = Self.start { await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOn)) }
    await Self.waitUntil { download.suspendedFetchCount == 1 && Self.sourceStates(model).last == .loaded(catalog) }
    #expect(Self.sourceStates(model) == [.loading, .loaded(catalog)])
    #expect(model.draft?.isLoading == true)

    download.resumeFetches(for: CatalogData.first)
    await Self.waitUntil { open.isFinished }
    #expect(model.draft?.sources.map(\.id) == [CatalogData.firstKey, CatalogData.secondKey])
    #expect(Self.sourceStates(model) == [.loaded(catalog), .loaded(catalog)])
    download.resumeFetches()
  }

  @Test("받는 중 새로 고침하면 앞 받기는 취소되어 그 결과가 들어가지 않고, 새 받기의 결과만 들어간다")
  func refreshWhileLoading() async throws {
    let download = CatalogData.fake()
    download.suspendFetches(for: CatalogData.first)
    let (model, _) = Self.catalogModel(
      preferences: PreferencesClientFake(urls: [CatalogData.firstRaw]),
      download: download
    )
    let open = Self.start { await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOn)) }
    await Self.waitUntil { download.suspendedFetchCount == 1 }

    let refresh = Self.start { await model.refreshButtonTapped() }
    // 앞 받기는 바깥 Task 취소로 빠지고, 새 받기가 같은 주소라 다시 멈춘다.
    await Self
      .waitUntil { open.isFinished && download.suspendedFetchCount == 1 && Self.fetchedURLs(download).count == 2 }
    #expect(Self.sourceStates(model) == [.loading])

    download.resumeFetches(for: CatalogData.first)
    await Self.waitUntil { refresh.isFinished }
    let catalog = try CatalogData.catalog(CatalogData.twoApps)
    #expect(Self.sourceStates(model) == [.loaded(catalog)])
    download.resumeFetches()
  }

  @Test("취소를 보지 않는 앞 받기가 새로 고침 뒤 늦게 성공해도 새 결과를 덮지 않는다")
  func lateResultAfterRefreshIsDropped() async throws {
    let download = LateCatalogDownload(late: CatalogData.betaOnly, fresh: CatalogData.twoApps)
    let (model, _) = Self.catalogModel(
      preferences: PreferencesClientFake(urls: [CatalogData.firstRaw]),
      download: download
    )
    let open = Self.start { await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOn)) }
    await Self.waitUntil { download.isLateWaiting }

    let refresh = Self.start { await model.refreshButtonTapped() }
    await Self.waitUntil { refresh.isFinished }
    let fresh = try CatalogData.catalog(CatalogData.twoApps)
    #expect(Self.sourceStates(model) == [.loaded(fresh)])

    download.openGate()
    await Self.waitUntil { open.isFinished }
    #expect(Self.sourceStates(model) == [.loaded(fresh)])
  }

  @Test("받는 중 닫으면 받기가 취소되고 시트가 닫히며, 메뉴 호출도 끝난다")
  func closeWhileLoading() async {
    let download = CatalogData.fake()
    download.suspendFetches()
    let (model, _) = Self.catalogModel(download: download)
    let open = Self.start { await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOn)) }
    await Self.waitUntil { download.suspendedFetchCount == 2 }

    model.cancelTapped()

    #expect(model.draft == nil)
    await Self.waitUntil { download.suspendedFetchCount == 0 && open.isFinished }
    download.resumeFetches()
    await Self.waitUntil { open.isFinished }
    #expect(model.draft == nil)
  }

  @Test("받는 중 닫고 곧바로 다시 열면 앞 받기의 늦은 결과가 새 시트에 들어가지 않는다")
  func lateResultAfterReopenIsDropped() async throws {
    let download = LateCatalogDownload(late: CatalogData.betaOnly, fresh: CatalogData.twoApps)
    let (model, _) = Self.catalogModel(
      preferences: PreferencesClientFake(urls: [CatalogData.firstRaw]),
      download: download
    )
    let open = Self.start { await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOn)) }
    await Self.waitUntil { download.isLateWaiting }

    model.sheetDismissed()
    let reopen = Self.start { await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOff)) }
    await Self.waitUntil { reopen.isFinished }
    let fresh = try CatalogData.catalog(CatalogData.twoApps)
    #expect(model.draft?.deviceID == SampleID.iPhoneOff)
    #expect(Self.sourceStates(model) == [.loaded(fresh)])

    download.openGate()
    await Self.waitUntil { open.isFinished }
    #expect(Self.sourceStates(model) == [.loaded(fresh)])
  }

  @Test("다른 카탈로그를 아직 읽는 중에 설치를 누르면 시트를 닫고 그 받기를 취소한다")
  func installCancelsLoading() async {
    let download = CatalogData.fake()
    download.suspendFetches(for: CatalogData.second)
    let (model, requests) = Self.catalogModel(download: download)
    let open = Self.start { await model.menuTapped(Self.sampleDevice(SampleID.iPhoneOn)) }
    await Self.waitUntil { download.suspendedFetchCount == 1 && model.draft?.sources.first?.state != .loading }
    model.appSelected(Self.alphaKey)

    await model.installButtonTapped()

    #expect(model.draft == nil)
    #expect(requests.values.map(\.buildURL) == [CatalogData.alphaV2URL])
    await Self.waitUntil { download.suspendedFetchCount == 0 && open.isFinished }
    download.resumeFetches()
    await Self.waitUntil { open.isFinished }
  }
}

/// 취소를 보지 않는 받기 흉내: 첫 `fetchData` 는 `openGate()` 까지 기다린 뒤 취소와 관계없이 `late` 로 성공하고,
/// 그 뒤 호출은 바로 `fresh` 로 성공한다 (해석처럼 취소를 보지 않는 단계의 늦은 결과).
private final class LateCatalogDownload: DownloadClient {
  private struct State {
    var fetchCount = 0
    var isGateOpen = false
    var waiting: CheckedContinuation<Void, Never>?
  }

  private let late: Data
  private let fresh: Data
  private let state = Mutex(State())

  init(late: Data, fresh: Data) {
    self.late = late
    self.fresh = fresh
  }

  /// 첫 호출이 문 앞에서 기다리는 중이다.
  var isLateWaiting: Bool {
    self.state.withLock { $0.waiting != nil }
  }

  func openGate() {
    let waiting: CheckedContinuation<Void, Never>? = self.state.withLock { state in
      state.isGateOpen = true
      let waiting = state.waiting
      state.waiting = nil
      return waiting
    }
    waiting?.resume()
  }

  func fetchData(_: DownloadURL, maxBytes _: Int) async throws(DownloadError) -> Data {
    let isFirst: Bool = self.state.withLock { state in
      state.fetchCount += 1
      return state.fetchCount == 1
    }
    guard isFirst else { return self.fresh }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let isOpen: Bool = self.state.withLock { state in
        guard !state.isGateOpen else { return true }
        state.waiting = continuation
        return false
      }
      if isOpen {
        continuation.resume()
      }
    }
    return self.late
  }

  func download(
    _: DownloadURL,
    onProgress _: @escaping @Sendable (DownloadProgress) async -> Void
  ) async throws(DownloadError) -> DownloadedFile {
    throw .failed
  }

  func removeDownloaded(_: DownloadedFile) async {}

  func removeLeftoverDownloads() async {}
}
