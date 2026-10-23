import Core
import DownloadInterface
import Foundation
import PreferencesInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

/// 카탈로그에서 설치 시트 상태(`CatalogInstallDraft`)의 규칙.
struct CatalogInstallDraftTests {
  static let device = LauncherNotice.Device(name: "iPhone 17 Pro", runtimeName: "iOS 27.0")
  static let alphaKey = CatalogAppKey(sourceID: CatalogData.firstKey, appID: CatalogData.alpha)
  static let betaKey = CatalogAppKey(sourceID: CatalogData.firstKey, appID: CatalogData.beta)

  static func draft() -> CatalogInstallDraft {
    CatalogInstallDraft(deviceID: SampleID.iPhoneOn, device: self.device)
  }

  static func setting(_ urls: [String], isLocked: Bool = false) -> CatalogURLSetting {
    CatalogURLSetting(urls: urls, isLocked: isLocked)
  }

  /// 첫 카탈로그만 등록해 `data` 로 읽고 alpha 를 고른 상태와 그 받기 식별자.
  static func loadedWithAlpha(_ data: Data = CatalogData.twoApps) throws -> (CatalogInstallDraft, UUID) {
    var draft = self.draft()
    let id = UUID()
    _ = draft.beginLoad(self.setting([CatalogData.firstRaw]), id: id)
    try draft.loaded(.success(CatalogData.catalog(data)), for: CatalogData.firstKey, id: id)
    draft.appSelected(self.alphaKey)
    return (draft, id)
  }

  @Test("beginLoad: 저장 순서대로 구역을 만들고, 쓸 수 있는 주소만 읽는 중·받기 대상이며, 쓸 수 없는 주소는 이유, 중복은 뺀다")
  func beginLoadBuildsSources() {
    var draft = Self.draft()
    let urls = [CatalogData.firstRaw, CatalogData.httpRaw, CatalogData.firstDuplicateRaw, "", CatalogData.secondRaw]

    let targets = draft.beginLoad(Self.setting(urls), id: UUID())

    #expect(draft.sources.map(\.id) == [CatalogData.firstKey, "invalid-1", "invalid-3", CatalogData.secondKey])
    #expect(draft.sources.map(\.raw) == [CatalogData.firstRaw, CatalogData.httpRaw, "", CatalogData.secondRaw])
    #expect(draft.sources.map(\.state) == [.loading, .invalid(.notHTTPS), .invalid(.empty), .loading])
    #expect(targets == [
      CatalogLoadTarget(sourceID: CatalogData.firstKey, url: CatalogData.first),
      CatalogLoadTarget(sourceID: CatalogData.secondKey, url: CatalogData.second),
    ])
    #expect(draft.isLoading)
  }

  @Test("loaded: 다른 받기 식별자의 결과와 없는 구역은 버리고, 지금 받기면 그 구역만 바꾼다")
  func loadedChecksLoadID() throws {
    var draft = Self.draft()
    let old = UUID()
    let current = UUID()
    _ = draft.beginLoad(Self.setting([CatalogData.firstRaw, CatalogData.secondRaw]), id: old)
    _ = draft.beginLoad(Self.setting([CatalogData.firstRaw, CatalogData.secondRaw]), id: current)
    let catalog = try CatalogData.catalog(CatalogData.twoApps)

    draft.loaded(.success(catalog), for: CatalogData.firstKey, id: old)
    #expect(draft.sources.map(\.state) == [.loading, .loading])

    draft.loaded(.success(catalog), for: "https://unknown.example.com/catalog.json", id: current)
    #expect(draft.sources.map(\.state) == [.loading, .loading])

    draft.loaded(.failure(.download(.httpStatus(404))), for: CatalogData.secondKey, id: current)
    #expect(draft.sources.map(\.state) == [.loading, .failed(.download(.httpStatus(404)))])
    draft.loaded(.success(catalog), for: CatalogData.firstKey, id: current)
    #expect(draft.sources.map(\.state) == [.loaded(catalog), .failed(.download(.httpStatus(404)))])
    #expect(!draft.isLoading)
  }

  @Test("새로 고침 뒤 같은 카탈로그·앱·버전이 다시 오면 선택을 유지하고, 읽는 동안은 고른 버전이 없다")
  func refreshKeepsSelection() throws {
    var (draft, _) = try Self.loadedWithAlpha()
    draft.versionSelected(CatalogData.alphaV1)
    let refresh = UUID()

    _ = draft.beginLoad(Self.setting([CatalogData.firstRaw]), id: refresh)
    #expect(draft.selectedApp == Self.alphaKey)
    #expect(draft.selectedVersionID == CatalogData.alphaV1)
    #expect(draft.selectedVersion == nil)
    #expect(!draft.canInstall)

    try draft.loaded(.success(CatalogData.catalog(CatalogData.twoApps)), for: CatalogData.firstKey, id: refresh)
    #expect(draft.selectedApp == Self.alphaKey)
    #expect(draft.selectedVersion?.id == CatalogData.alphaV1)
    #expect(draft.canInstall)
  }

  @Test("새로 고침 뒤 고른 버전만 사라지면 버전 선택만 비우고(다른 버전으로 바꾸지 않는다), 앱이 사라지거나 실패면 선택을 비운다")
  func refreshDropsMissingSelection() throws {
    var (versionGone, _) = try Self.loadedWithAlpha()
    let first = UUID()
    _ = versionGone.beginLoad(Self.setting([CatalogData.firstRaw]), id: first)
    try versionGone.loaded(.success(CatalogData.catalog(CatalogData.alphaV1Only)), for: CatalogData.firstKey, id: first)
    #expect(versionGone.selectedApp == Self.alphaKey)
    #expect(versionGone.selectedVersionID == nil)
    #expect(!versionGone.canInstall)

    var (appGone, _) = try Self.loadedWithAlpha()
    let second = UUID()
    _ = appGone.beginLoad(Self.setting([CatalogData.firstRaw]), id: second)
    try appGone.loaded(.success(CatalogData.catalog(CatalogData.betaOnly)), for: CatalogData.firstKey, id: second)
    #expect(appGone.selectedApp == nil)
    #expect(appGone.selectedVersionID == nil)

    var (failed, _) = try Self.loadedWithAlpha()
    let third = UUID()
    _ = failed.beginLoad(Self.setting([CatalogData.firstRaw]), id: third)
    failed.loaded(.failure(.catalog(.notJSONObject)), for: CatalogData.firstKey, id: third)
    #expect(failed.selectedApp == nil)
    #expect(failed.selectedVersionID == nil)
  }

  @Test("고른 카탈로그가 새 설정에서 지워졌거나 쓸 수 없는 주소가 되면 beginLoad 가 바로 선택을 비운다")
  func beginLoadDropsSelectionOfRemovedSource() throws {
    var (removed, _) = try Self.loadedWithAlpha()
    _ = removed.beginLoad(Self.setting([CatalogData.secondRaw]), id: UUID())
    #expect(removed.selectedApp == nil)
    #expect(removed.selectedVersionID == nil)

    var (invalid, _) = try Self.loadedWithAlpha()
    _ = invalid.beginLoad(Self.setting([CatalogData.httpRaw, CatalogData.secondRaw]), id: UUID())
    #expect(invalid.selectedApp == nil)

    // 같은 카탈로그를 다른 표기로 다시 등록했으면(키가 같다) 그대로 둔다.
    var (same, _) = try Self.loadedWithAlpha()
    _ = same.beginLoad(Self.setting([CatalogData.firstDuplicateRaw]), id: UUID())
    #expect(same.selectedApp == Self.alphaKey)
  }

  @Test("appSelected: 읽힌 앱이면 가장 새 버전을 고르고, 버전 없는 앱은 버전 없이, 읽히지 않은 구역·없는 앱·nil 이면 선택을 비운다")
  func appSelection() throws {
    var (draft, _) = try Self.loadedWithAlpha()
    #expect(draft.selectedApp == Self.alphaKey)
    #expect(draft.selectedVersionID == CatalogData.alphaV2)

    draft.appSelected(Self.betaKey)
    #expect(draft.selectedVersionID == CatalogData.betaV1)
    draft.appSelected(CatalogAppKey(sourceID: CatalogData.firstKey, appID: BuildCatalog.AppID("missing")))
    #expect(draft.selectedApp == nil)
    #expect(draft.selectedVersionID == nil)
    draft.appSelected(Self.alphaKey)
    draft.appSelected(nil)
    #expect(draft.selectedApp == nil)

    var loading = Self.draft()
    _ = loading.beginLoad(Self.setting([CatalogData.firstRaw]), id: UUID())
    loading.appSelected(Self.alphaKey)
    #expect(loading.selectedApp == nil)

    var (noVersions, _) = try Self.loadedWithAlpha(CatalogData.alphaWithoutVersions)
    #expect(noVersions.selectedApp == Self.alphaKey)
    #expect(noVersions.selectedVersionID == nil)
    noVersions.versionSelected(CatalogData.alphaV1)
    #expect(noVersions.selectedVersionID == nil)
  }

  @Test("versionSelected: 고른 앱의 버전만 고르고, 다른 앱의 버전이나 nil 은 무시한다")
  func versionSelection() throws {
    var (draft, _) = try Self.loadedWithAlpha()

    draft.versionSelected(CatalogData.alphaV1)
    #expect(draft.selectedVersionID == CatalogData.alphaV1)
    draft.versionSelected(CatalogData.betaV1)
    #expect(draft.selectedVersionID == CatalogData.alphaV1)
    draft.versionSelected(nil)
    #expect(draft.selectedVersionID == CatalogData.alphaV1)
    #expect(draft.selectedVersion?.buildURL == DownloadURL("https://builds.example.com/alpha-1.zip"))

    var closed = Self.draft()
    closed.versionSelected(CatalogData.alphaV1)
    #expect(closed.selectedVersionID == nil)
    #expect(!closed.canInstall)
  }

  @Test("카탈로그 사이의 같은 앱 id 는 다른 줄이고, 고르면 그 카탈로그의 버전이 나온다")
  func sameAppIDAcrossCatalogs() throws {
    var draft = Self.draft()
    let id = UUID()
    _ = draft.beginLoad(Self.setting([CatalogData.firstRaw, CatalogData.secondRaw]), id: id)
    try draft.loaded(.success(CatalogData.catalog(CatalogData.twoApps)), for: CatalogData.firstKey, id: id)
    try draft.loaded(.success(CatalogData.catalog(CatalogData.alphaV1Only)), for: CatalogData.secondKey, id: id)
    let secondAlpha = CatalogAppKey(sourceID: CatalogData.secondKey, appID: CatalogData.alpha)
    #expect(secondAlpha != Self.alphaKey)

    draft.appSelected(secondAlpha)
    #expect(draft.selectedVersion?.id == CatalogData.alphaV1)
    #expect(draft.selectedAppValue?.versions.map(\.id) == [CatalogData.alphaV1])
    draft.appSelected(Self.alphaKey)
    #expect(draft.selectedVersion?.id == CatalogData.alphaV2)

    // 다른 카탈로그가 실패해도 고른 앱의 카탈로그가 아니면 선택은 그대로다.
    let refresh = UUID()
    _ = draft.beginLoad(Self.setting([CatalogData.firstRaw, CatalogData.secondRaw]), id: refresh)
    draft.loaded(.failure(.download(.offline)), for: CatalogData.secondKey, id: refresh)
    #expect(draft.selectedApp == Self.alphaKey)
  }

  @Test("잠금·빈 목록·읽는 중을 설정과 구역 상태로 알리고, 설정 열기는 빈 목록이고 잠기지 않았을 때만이다")
  func lockEmptyLoadingAndOpenSettings() {
    var empty = Self.draft()
    _ = empty.beginLoad(Self.setting([]), id: UUID())
    #expect(empty.isEmpty)
    #expect(!empty.isLocked)
    #expect(!empty.isLoading)
    #expect(empty.showsOpenSettings)

    var lockedEmpty = Self.draft()
    _ = lockedEmpty.beginLoad(Self.setting([], isLocked: true), id: UUID())
    #expect(lockedEmpty.isEmpty)
    #expect(lockedEmpty.isLocked)
    #expect(!lockedEmpty.showsOpenSettings)

    var withSources = Self.draft()
    _ = withSources.beginLoad(Self.setting([CatalogData.httpRaw]), id: UUID())
    #expect(!withSources.isEmpty)
    #expect(!withSources.isLoading)
    #expect(!withSources.showsOpenSettings)

    // 잠금은 마지막으로 읽은 설정을 따른다.
    var relocked = Self.draft()
    _ = relocked.beginLoad(Self.setting([CatalogData.firstRaw], isLocked: true), id: UUID())
    #expect(relocked.isLocked)
    #expect(relocked.isLoading)
    _ = relocked.beginLoad(Self.setting([CatalogData.firstRaw]), id: UUID())
    #expect(!relocked.isLocked)
  }

  @Test("versionPane: 선택 없음, 고른 앱의 카탈로그를 다시 읽는 중, 버전 없는 앱, 그 밖은 Core 순서 그대로의 버전 목록")
  func versionPane() throws {
    var draft = Self.draft()
    #expect(draft.versionPane == .noSelection)

    (draft, _) = try Self.loadedWithAlpha()
    let catalog = try CatalogData.catalog(CatalogData.twoApps)
    let alphaVersions = try #require(catalog.apps.first?.versions)
    #expect(alphaVersions.map(\.id) == [CatalogData.alphaV2, CatalogData.alphaV1])
    #expect(draft.versionPane == .versions(alphaVersions))

    _ = draft.beginLoad(Self.setting([CatalogData.firstRaw]), id: UUID())
    #expect(draft.versionPane == .loading)

    let (noVersions, _) = try Self.loadedWithAlpha(CatalogData.alphaWithoutVersions)
    #expect(noVersions.versionPane == .noVersions)
  }

  @Test("구역 상태 줄은 실패 이유·쓸 수 없는 주소와 마지막으로 읽은 설정의 잠김을 담고, 읽는 중·읽힌 구역은 없다", arguments: [true, false])
  func sourceNotesCarryLock(isLocked: Bool) throws {
    var draft = Self.draft()
    let id = UUID()
    let urls = [CatalogData.firstRaw, CatalogData.httpRaw, CatalogData.secondRaw]
    _ = draft.beginLoad(Self.setting(urls, isLocked: isLocked), id: id)
    #expect(draft.sources.map { draft.note(for: $0) } == [nil, .invalid(.notHTTPS, isLocked: isLocked), nil])

    draft.loaded(.failure(.download(.httpStatus(404))), for: CatalogData.firstKey, id: id)
    try draft.loaded(.success(CatalogData.catalog(CatalogData.twoApps)), for: CatalogData.secondKey, id: id)

    #expect(draft.sources.map { draft.note(for: $0) } == [
      .failed(.download(.httpStatus(404)), isLocked: isLocked), .invalid(.notHTTPS, isLocked: isLocked), nil,
    ])
  }
}
