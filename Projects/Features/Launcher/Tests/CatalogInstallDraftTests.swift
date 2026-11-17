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

  /// 첫 카탈로그만 등록해 `previous` 로 읽은 뒤(선택 없음) 새로 고침을 시작한 상태와 그 새 받기 식별자.
  static func reloading(_ previous: Data = CatalogData.twoApps) throws -> (CatalogInstallDraft, UUID) {
    var draft = self.draft()
    let first = UUID()
    _ = draft.beginLoad(self.setting([CatalogData.firstRaw]), id: first)
    try draft.loaded(.success(CatalogData.catalog(previous)), for: CatalogData.firstKey, id: first)
    let refresh = UUID()
    _ = draft.beginLoad(self.setting([CatalogData.firstRaw]), id: refresh)
    return (draft, refresh)
  }

  /// 주소의 구역 id.
  static func key(_ raw: String) -> CatalogSource.ID {
    DownloadURL(raw)!.comparisonKey
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

  @Test("v2 카탈로그는 iOS 앱만 고를 수 있다: 같은 id 면 iOS 앱을 고르고, Android 앱만 있는 id 는 선택을 비운다")
  func schemaVersion2SelectsIOSAppsOnly() throws {
    let (draft, _) = try Self.loadedWithAlpha(CatalogData.v2Mixed)

    #expect(draft.selectedApp == Self.alphaKey)
    #expect(draft.selectedAppValue?.platform == .ios)
    #expect(draft.selectedAppValue?.name == "Alpha")
    #expect(draft.selectedVersionID == CatalogData.alphaV1)

    var androidOnly = draft
    androidOnly.appSelected(Self.betaKey)
    #expect(androidOnly.selectedApp == nil)
    #expect(androidOnly.selectedVersionID == nil)
  }

  @Test("새로 고침 뒤 고른 앱이 Android 앱이 되면 사라진 앱처럼 선택을 비운다")
  func refreshClearsSelectionWhenAppBecomesAndroid() throws {
    var (draft, _) = try Self.loadedWithAlpha()
    let refresh = UUID()

    _ = draft.beginLoad(Self.setting([CatalogData.firstRaw]), id: refresh)
    let android = try CatalogData.catalog(CatalogData.v2AlphaAndroidOnly)
    draft.loaded(.success(android), for: CatalogData.firstKey, id: refresh)

    #expect(draft.selectedApp == nil)
    #expect(draft.selectedVersionID == nil)
    #expect(draft.selectedVersion == nil)
  }

  @Test("새로 고침 뒤 같은 카탈로그·앱·버전이 다시 오면 선택을 유지하고, 읽는 동안은 앞 앱·버전 목록을 보이되 설치할 수 없다")
  func refreshKeepsSelection() throws {
    var (draft, _) = try Self.loadedWithAlpha()
    draft.versionSelected(CatalogData.alphaV1)
    let refresh = UUID()
    let catalog = try CatalogData.catalog(CatalogData.twoApps)
    let alphaVersions = try #require(catalog.apps.first?.versions)

    _ = draft.beginLoad(Self.setting([CatalogData.firstRaw]), id: refresh)
    #expect(draft.sources.map(\.state) == [.reloading(catalog)])
    #expect(draft.selectedApp == Self.alphaKey)
    #expect(draft.selectedAppValue?.id == CatalogData.alpha)
    #expect(draft.versionPane == .versions(alphaVersions))
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
}

extension CatalogInstallDraftTests {
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

  @Test("versionPane: 선택 없음, 버전 없는 앱, 그 밖은 Core 순서 그대로의 버전 목록 (다시 읽는 중에는 앞 버전 목록)")
  func versionPane() throws {
    var draft = Self.draft()
    #expect(draft.versionPane == .noSelection)

    (draft, _) = try Self.loadedWithAlpha()
    let catalog = try CatalogData.catalog(CatalogData.twoApps)
    let alphaVersions = try #require(catalog.apps.first?.versions)
    #expect(alphaVersions.map(\.id) == [CatalogData.alphaV2, CatalogData.alphaV1])
    #expect(draft.versionPane == .versions(alphaVersions))

    _ = draft.beginLoad(Self.setting([CatalogData.firstRaw]), id: UUID())
    #expect(draft.versionPane == .versions(alphaVersions))

    let (noVersions, _) = try Self.loadedWithAlpha(CatalogData.alphaWithoutVersions)
    #expect(noVersions.versionPane == .noVersions)
  }

  @Test("emptyReason: 읽힌 구역에 앱이 없으면 noApps, Android 앱만 있으면 noIOSApps, iOS 앱이 있거나 읽는 중·실패면 nil")
  func emptyReasons() throws {
    var draft = Self.draft()
    let id = UUID()
    let urls = [CatalogData.firstRaw, CatalogData.secondRaw, CatalogData.httpRaw]
    _ = draft.beginLoad(Self.setting(urls), id: id)
    #expect(draft.sources.map { draft.emptyReason(for: $0) } == [nil, nil, nil])

    try draft.loaded(.success(CatalogData.catalog(CatalogData.emptyApps)), for: CatalogData.firstKey, id: id)
    try draft.loaded(.success(CatalogData.catalog(CatalogData.v2AlphaAndroidOnly)), for: CatalogData.secondKey, id: id)
    #expect(draft.sources.map { draft.emptyReason(for: $0) } == [.noApps, .noIOSApps, nil])

    try draft.loaded(.success(CatalogData.catalog(CatalogData.v2Mixed)), for: CatalogData.firstKey, id: id)
    draft.loaded(.failure(.download(.httpStatus(404))), for: CatalogData.secondKey, id: id)
    #expect(draft.sources.map { draft.emptyReason(for: $0) } == [nil, nil, nil])
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

  // MARK: - 새로 고침 중 (앞 결과 유지)

  @Test("새로 고침: 읽힌 구역은 앞 결과를 보이며 다시 읽고, 실패·읽는 중이던 구역과 새로 등록한 구역은 읽는 중이며, 거듭 새로 고쳐도 앞 결과를 그대로 둔다")
  func beginLoadKeepsLoadedCatalogs() throws {
    var draft = Self.draft()
    let first = UUID()
    _ = draft.beginLoad(Self.setting([CatalogData.firstRaw, CatalogData.secondRaw]), id: first)
    let catalog = try CatalogData.catalog(CatalogData.twoApps)
    draft.loaded(.success(catalog), for: CatalogData.firstKey, id: first)
    draft.loaded(.failure(.download(.offline)), for: CatalogData.secondKey, id: first)
    let urls = [CatalogData.firstRaw, CatalogData.secondRaw, "https://cdn.example.org/new/catalog.json"]

    let refresh = UUID()
    _ = draft.beginLoad(Self.setting(urls), id: refresh)
    #expect(draft.sources.map(\.state) == [.reloading(catalog), .loading, .loading])
    #expect(draft.isLoading)
    #expect(draft.note(for: draft.sources[0]) == nil)
    #expect(draft.appRows(in: draft.sources[0]).map(\.name) == ["Alpha", "Beta"])

    let again = UUID()
    _ = draft.beginLoad(Self.setting(urls), id: again)
    #expect(draft.sources.map(\.state) == [.reloading(catalog), .loading, .loading])
    // 옛 받기의 늦은 결과는 버린다.
    try draft.loaded(.success(CatalogData.catalog(CatalogData.betaOnly)), for: CatalogData.firstKey, id: refresh)
    #expect(draft.sources.map(\.state) == [.reloading(catalog), .loading, .loading])

    // 첫 받기가 끝나기 전에 새로 고치면 읽는 중 그대로다.
    var unfinished = Self.draft()
    _ = unfinished.beginLoad(Self.setting([CatalogData.firstRaw]), id: UUID())
    _ = unfinished.beginLoad(Self.setting([CatalogData.firstRaw]), id: UUID())
    #expect(unfinished.sources.map(\.state) == [.loading])

    // 앞 결과에 앱이 없으면 다시 읽는 중에도 그 이유를 보인다.
    let (empty, _) = try Self.reloading(CatalogData.emptyApps)
    let emptyCatalog = try CatalogData.catalog(CatalogData.emptyApps)
    #expect(empty.sources.map(\.state) == [.reloading(emptyCatalog)])
    #expect(empty.emptyReason(for: empty.sources[0]) == .noApps)
    #expect(empty.appRows(in: empty.sources[0]).isEmpty)
  }

  @Test("다시 읽는 중에도 앞 목록의 앱·버전을 고를 수 있고, 그 구역 결과가 오기 전에는 설치할 수 없으며, 결과가 오면 선택 유지·비우기 규칙대로 확인한다")
  func selectWhileReloading() throws {
    var draft = Self.draft()
    let first = UUID()
    _ = draft.beginLoad(Self.setting([CatalogData.firstRaw, CatalogData.secondRaw]), id: first)
    try draft.loaded(.success(CatalogData.catalog(CatalogData.twoApps)), for: CatalogData.firstKey, id: first)
    draft.loaded(.failure(.download(.offline)), for: CatalogData.secondKey, id: first)
    let refresh = UUID()
    _ = draft.beginLoad(Self.setting([CatalogData.firstRaw, CatalogData.secondRaw]), id: refresh)

    draft.appSelected(Self.betaKey)
    #expect(draft.selectedApp == Self.betaKey)
    #expect(draft.selectedVersionID == CatalogData.betaV1)
    #expect(draft.selectedVersion == nil)
    #expect(!draft.canInstall)

    draft.appSelected(Self.alphaKey)
    #expect(draft.selectedVersionID == CatalogData.alphaV2)
    draft.versionSelected(CatalogData.alphaV1)
    #expect(draft.selectedVersionID == CatalogData.alphaV1)
    #expect(!draft.canInstall)

    // 앞 결과가 없는(읽는 중) 구역의 앱은 고를 수 없다.
    draft.appSelected(CatalogAppKey(sourceID: CatalogData.secondKey, appID: CatalogData.alpha))
    #expect(draft.selectedApp == nil)
    #expect(draft.selectedVersionID == nil)

    draft.appSelected(Self.betaKey)
    try draft.loaded(.success(CatalogData.catalog(CatalogData.twoApps)), for: CatalogData.firstKey, id: refresh)
    #expect(draft.selectedApp == Self.betaKey)
    #expect(draft.selectedVersion?.id == CatalogData.betaV1)
    #expect(draft.canInstall)
  }

  @Test("다시 읽는 중 앱을 고르며 자동으로 골라진 버전은 결과가 오면 새 결과의 가장 새 버전으로 다시 고르고, 직접 고른 버전은 같은 id 가 있으면 유지·없으면 버전 선택만 비운다")
  func autoPickedVersionFollowsNewResult() throws {
    // (a) 앞 결과에 없던 더 새 버전이 오면 그것으로 다시 고른다.
    let (newerStart, newerID) = try Self.reloading(CatalogData.alphaV1Only)
    var newer = newerStart
    newer.appSelected(Self.alphaKey)
    #expect(newer.selectedVersionID == CatalogData.alphaV1)
    try newer.loaded(.success(CatalogData.catalog(CatalogData.twoApps)), for: CatalogData.firstKey, id: newerID)
    #expect(newer.selectedVersionID == CatalogData.alphaV2)
    #expect(newer.canInstall)

    // (b) 저절로 고른 버전이 사라지면 비우지 않고 새 결과의 가장 새 버전을 고른다.
    let (olderStart, olderID) = try Self.reloading(CatalogData.twoApps)
    var older = olderStart
    older.appSelected(Self.alphaKey)
    #expect(older.selectedVersionID == CatalogData.alphaV2)
    try older.loaded(.success(CatalogData.catalog(CatalogData.alphaV1Only)), for: CatalogData.firstKey, id: olderID)
    #expect(older.selectedVersionID == CatalogData.alphaV1)
    #expect(older.canInstall)

    // (c) 직접 고른 버전은 같은 id 가 있으면 유지하고, 없으면 버전 선택만 비운다.
    let (pickedStart, pickedID) = try Self.reloading(CatalogData.twoApps)
    var picked = pickedStart
    picked.appSelected(Self.alphaKey)
    picked.versionSelected(CatalogData.alphaV1)
    var pickedGone = picked
    try picked.loaded(.success(CatalogData.catalog(CatalogData.twoApps)), for: CatalogData.firstKey, id: pickedID)
    #expect(picked.selectedVersionID == CatalogData.alphaV1)
    try pickedGone.loaded(
      .success(CatalogData.catalog(CatalogData.alphaWithoutVersions)),
      for: CatalogData.firstKey,
      id: pickedID
    )
    #expect(pickedGone.selectedApp == Self.alphaKey)
    #expect(pickedGone.selectedVersionID == nil)

    // (d) 저절로 고른 뒤 거듭 새로 고치면 마지막 받기 결과에서 다시 고른다.
    let (twiceStart, firstRefresh) = try Self.reloading(CatalogData.alphaV1Only)
    var twice = twiceStart
    twice.appSelected(Self.alphaKey)
    let secondRefresh = UUID()
    _ = twice.beginLoad(Self.setting([CatalogData.firstRaw]), id: secondRefresh)
    try twice.loaded(.success(CatalogData.catalog(CatalogData.twoApps)), for: CatalogData.firstKey, id: firstRefresh)
    #expect(twice.selectedVersionID == CatalogData.alphaV1)
    try twice.loaded(.success(CatalogData.catalog(CatalogData.twoApps)), for: CatalogData.firstKey, id: secondRefresh)
    #expect(twice.selectedVersionID == CatalogData.alphaV2)

    // (e) 읽힌 구역에서 고른 뒤 새로 고치면 기존 규칙대로 사라진 버전은 버전 선택만 비운다.
    var (settled, _) = try Self.loadedWithAlpha()
    let refresh = UUID()
    _ = settled.beginLoad(Self.setting([CatalogData.firstRaw]), id: refresh)
    try settled.loaded(.success(CatalogData.catalog(CatalogData.alphaV1Only)), for: CatalogData.firstKey, id: refresh)
    #expect(settled.selectedApp == Self.alphaKey)
    #expect(settled.selectedVersionID == nil)
  }

  @Test("다시 받기가 실패한 구역은 앞 목록을 지우고 실패 이유를 보이며, 그 구역 선택을 비운다")
  func reloadFailureClearsList() throws {
    let (start, refresh) = try Self.reloading()
    var draft = start
    draft.appSelected(Self.alphaKey)

    draft.loaded(.failure(.download(.offline)), for: CatalogData.firstKey, id: refresh)

    #expect(draft.sources.map(\.state) == [.failed(.download(.offline))])
    #expect(draft.appRows(in: draft.sources[0]).isEmpty)
    #expect(draft.note(for: draft.sources[0]) == .failed(.download(.offline), isLocked: false))
    #expect(draft.selectedApp == nil)
    #expect(draft.versionPane == .noSelection)
    #expect(!draft.canInstall)
    #expect(!draft.isLoading)
  }

  @Test("다른 구역이 아직 다시 읽는 중이어도 결과가 온 구역의 고른 버전은 설치할 수 있다")
  func otherSourceSettledWhileReloading() throws {
    var draft = Self.draft()
    let first = UUID()
    let setting = Self.setting([CatalogData.firstRaw, CatalogData.secondRaw])
    let catalog = try CatalogData.catalog(CatalogData.twoApps)
    _ = draft.beginLoad(setting, id: first)
    draft.loaded(.success(catalog), for: CatalogData.firstKey, id: first)
    draft.loaded(.success(catalog), for: CatalogData.secondKey, id: first)
    let refresh = UUID()
    _ = draft.beginLoad(setting, id: refresh)
    draft.loaded(.success(catalog), for: CatalogData.firstKey, id: refresh)

    draft.appSelected(Self.alphaKey)
    #expect(draft.canInstall)
    draft.appSelected(CatalogAppKey(sourceID: CatalogData.secondKey, appID: CatalogData.alpha))
    #expect(!draft.canInstall)
    #expect(draft.isLoading)

    draft.loaded(.success(catalog), for: CatalogData.secondKey, id: refresh)
    #expect(!draft.isLoading)
    #expect(draft.canInstall)
  }

  @Test("앱 줄 id 는 카탈로그와 앱 id 의 쌍이라 카탈로그 사이에 같은 앱 id 가 있어도 모든 줄 id 가 다르고, 고르면 그 줄 카탈로그의 버전·빌드 주소가 나온다")
  func appRowsUniqueAcrossCatalogs() throws {
    let mixedRaw = "https://cdn.example.org/mixed/catalog.json"
    let failedRaw = "https://cdn.example.org/failed/catalog.json"
    let loadingRaw = "https://cdn.example.org/loading/catalog.json"
    var draft = Self.draft()
    let id = UUID()
    let urls = [CatalogData.firstRaw, CatalogData.secondRaw, mixedRaw, failedRaw, loadingRaw, CatalogData.httpRaw]
    _ = draft.beginLoad(Self.setting(urls), id: id)
    try draft.loaded(.success(CatalogData.catalog(CatalogData.twoApps)), for: CatalogData.firstKey, id: id)
    try draft.loaded(.success(CatalogData.catalog(CatalogData.alphaV1Only)), for: CatalogData.secondKey, id: id)
    try draft.loaded(.success(CatalogData.catalog(CatalogData.v2Mixed)), for: Self.key(mixedRaw), id: id)
    draft.loaded(.failure(.download(.offline)), for: Self.key(failedRaw), id: id)

    let rows = draft.sources.flatMap { draft.appRows(in: $0) }
    #expect(Set(rows.map(\.id)).count == rows.count)
    #expect(rows.map(\.name) == ["Alpha", "Beta", "Alpha", "Beta", "Alpha"])
    // v2 의 같은 id iOS·Android 앱은 iOS 한 줄만.
    #expect(draft.appRows(in: draft.sources[2]) == [
      CatalogAppRow(id: CatalogAppKey(sourceID: Self.key(mixedRaw), appID: CatalogData.alpha), name: "Alpha"),
    ])
    // 실패·읽는 중·쓸 수 없는 주소 구역은 줄이 없다.
    #expect(draft.sources[3...].map { draft.appRows(in: $0) } == [[], [], []])

    let alphaRows = rows.filter { $0.id.appID == CatalogData.alpha }
    var buildURLs: [DownloadURL?] = []
    for row in alphaRows {
      draft.appSelected(row.id)
      #expect(draft.selectedApp == row.id)
      buildURLs.append(draft.selectedVersion?.buildURL)
    }
    #expect(buildURLs == [CatalogData.alphaV2URL, CatalogData.alphaV1URL, CatalogData.alphaV1URL])
  }
}
