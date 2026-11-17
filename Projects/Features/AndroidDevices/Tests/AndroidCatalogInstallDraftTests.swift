import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import DownloadInterface
import Foundation
import PreferencesInterface
import Testing
@testable import AndroidDevicesFeature

/// 카탈로그에서 설치 시트 상태(`AndroidCatalogInstallDraft`)의 새로 고침·앱 줄 규칙. iOS `CatalogInstallDraftTests` 와 같은 제목·검증.
@MainActor
struct AndroidCatalogInstallDraftTests {
  static let v2Key = AndroidCatalogData.catalogV2.comparisonKey
  static let qaKey = AndroidCatalogData.qaURL.comparisonKey
  static let sampleKey = AndroidCatalogAppKey(sourceID: v2Key, appID: AndroidCatalogData.sampleID)
  static let emptyAppKey = AndroidCatalogAppKey(sourceID: v2Key, appID: AndroidCatalogData.emptyAppID)
  static let qaSampleKey = AndroidCatalogAppKey(sourceID: qaKey, appID: AndroidCatalogData.sampleID)

  static func draft() -> AndroidCatalogInstallDraft {
    AndroidCatalogInstallDraft(targets: [
      AndroidTargetDevice(
        id: AndroidVirtualDevice.bootedTabletSample.id,
        label: AndroidDeviceLabel(.bootedTabletSample)
      ),
    ])
  }

  static func setting(_ urls: [String], isLocked: Bool = false) -> CatalogURLSetting {
    CatalogURLSetting(urls: urls, isLocked: isLocked)
  }

  /// v2 주소 하나만 등록해 `data` 로 읽은 상태.
  static func loaded(_ data: Data = AndroidCatalogData.v2JSON) throws -> AndroidCatalogInstallDraft {
    var draft = self.draft()
    let id = UUID()
    _ = draft.beginLoad(self.setting([AndroidCatalogData.v2Raw]), id: id)
    try draft.loaded(.success(AndroidCatalogData.catalog(data)), for: self.v2Key, id: id)
    return draft
  }

  /// 같은 설정으로 다시 받기를 시작하고 새 받기 식별자를 돌려준다.
  static func refresh(_ draft: inout AndroidCatalogInstallDraft, urls: [String] = [AndroidCatalogData.v2Raw]) -> UUID {
    let id = UUID()
    _ = draft.beginLoad(self.setting(urls), id: id)
    return id
  }

  static func sampleVersions(_ data: Data = AndroidCatalogData.v2JSON) throws -> [BuildCatalog.Version] {
    try #require(AndroidCatalogData.catalog(data).app(AndroidCatalogData.sampleID, for: .android)).versions
  }

  @Test("새로 고침: 읽힌 구역은 앞 결과를 보이며 다시 읽고, 실패·읽는 중이던 구역과 새로 등록한 구역은 읽는 중이며, 거듭 새로 고쳐도 앞 결과를 그대로 둔다")
  func beginLoadKeepsLoadedCatalogs() throws {
    var draft = Self.draft()
    let urls = [AndroidCatalogData.v2Raw, AndroidCatalogData.iOSOnlyRaw, AndroidCatalogData.emptyRaw]
    let first = Self.refresh(&draft, urls: urls)
    let v2Catalog = try AndroidCatalogData.catalog(AndroidCatalogData.v2JSON)
    let empty = try AndroidCatalogData.catalog(AndroidCatalogData.emptyJSON)
    draft.loaded(.success(v2Catalog), for: Self.v2Key, id: first)
    draft.loaded(.failure(.download(.offline)), for: AndroidCatalogData.iOSOnly.comparisonKey, id: first)
    draft.loaded(.success(empty), for: AndroidCatalogData.empty.comparisonKey, id: first)
    #expect(!draft.isLoading)

    let refreshed = urls + [AndroidCatalogData.newRaw]
    let old = Self.refresh(&draft, urls: refreshed)
    #expect(draft.sources.map(\.state) == [.reloading(v2Catalog), .loading, .reloading(empty), .loading])
    #expect(draft.isLoading)
    #expect(draft.note(for: draft.sources[0]) == nil)
    #expect(draft.appRows(in: draft.sources[0]).map(\.name) == ["Sample (Android)", "Empty"])
    #expect(draft.emptyReason(for: draft.sources[2]) == .noApps)

    let current = Self.refresh(&draft, urls: refreshed)
    #expect(draft.sources.map(\.state) == [.reloading(v2Catalog), .loading, .reloading(empty), .loading])
    let newer = try AndroidCatalogData.catalog(AndroidCatalogData.newestOnlyJSON)
    draft.loaded(.success(newer), for: Self.v2Key, id: old)
    #expect(draft.sources[0].state == .reloading(v2Catalog))
    draft.loaded(.success(newer), for: Self.v2Key, id: current)
    #expect(draft.sources[0].state == .loaded(newer))

    var fresh = Self.draft()
    _ = Self.refresh(&fresh)
    _ = Self.refresh(&fresh)
    #expect(fresh.sources.map(\.state) == [.loading])
  }

  @Test("다시 읽는 중에도 앞 목록의 앱·버전을 고를 수 있고, 그 구역 결과가 오기 전에는 설치할 수 없으며, 결과가 오면 선택 유지·비우기 규칙대로 확인한다")
  func selectWhileReloading() throws {
    var draft = try Self.loaded()
    let id = Self.refresh(&draft, urls: [AndroidCatalogData.v2Raw, AndroidCatalogData.qaRaw])

    draft.appSelected(Self.sampleKey)
    #expect(draft.selectedApp == Self.sampleKey)
    #expect(draft.selectedVersionID == AndroidCatalogData.newest)
    #expect(try draft.versionPane == .versions(Self.sampleVersions()))
    #expect(draft.selectedVersion == nil)
    #expect(!draft.canInstall)

    draft.versionSelected(AndroidCatalogData.older)
    #expect(draft.selectedVersionID == AndroidCatalogData.older)
    #expect(!draft.canInstall)

    try draft.loaded(.success(AndroidCatalogData.catalog(AndroidCatalogData.v2JSON)), for: Self.v2Key, id: id)
    #expect(draft.canInstall)
    #expect(draft.selectedVersion?.id == AndroidCatalogData.older)

    draft.appSelected(Self.qaSampleKey)
    #expect(draft.selectedApp == nil)
    #expect(draft.selectedVersionID == nil)
  }

  @Test("다시 읽는 중 앱을 고르며 자동으로 골라진 버전은 결과가 오면 새 결과의 가장 새 버전으로 다시 고르고, 직접 고른 버전은 같은 id 가 있으면 유지·없으면 버전 선택만 비운다")
  func autoPickedVersionFollowsNewResult() throws {
    let v2Catalog = try AndroidCatalogData.catalog(AndroidCatalogData.v2JSON)
    let olderOnly = try AndroidCatalogData.catalog(AndroidCatalogData.olderOnlyJSON)
    let noVersions = try AndroidCatalogData.catalog(AndroidCatalogData.sampleWithoutVersionsJSON)

    // (a) 버전이 늘어난 결과: 앞 결과의 가장 새 버전(42)에서 새 결과의 가장 새 버전(43)으로.
    var grown = try Self.loaded(AndroidCatalogData.olderOnlyJSON)
    var id = Self.refresh(&grown)
    grown.appSelected(Self.sampleKey)
    #expect(grown.selectedVersionID == AndroidCatalogData.older)
    grown.loaded(.success(v2Catalog), for: Self.v2Key, id: id)
    #expect(grown.selectedVersionID == AndroidCatalogData.newest)
    #expect(grown.canInstall)

    // (b) 버전이 줄어든 결과: 자동이라 비우지 않고 남은 가장 새 버전으로.
    var shrunk = try Self.loaded()
    id = Self.refresh(&shrunk)
    shrunk.appSelected(Self.sampleKey)
    #expect(shrunk.selectedVersionID == AndroidCatalogData.newest)
    shrunk.loaded(.success(olderOnly), for: Self.v2Key, id: id)
    #expect(shrunk.selectedVersionID == AndroidCatalogData.older)
    #expect(shrunk.canInstall)

    // (c) 직접 고른 버전: 같은 id 가 있으면 유지, 앱에 버전이 없으면 버전 선택만 비운다.
    var picked = try Self.loaded()
    id = Self.refresh(&picked)
    picked.appSelected(Self.sampleKey)
    picked.versionSelected(AndroidCatalogData.older)
    var pickedAgain = picked
    picked.loaded(.success(v2Catalog), for: Self.v2Key, id: id)
    #expect(picked.selectedVersionID == AndroidCatalogData.older)
    pickedAgain.loaded(.success(noVersions), for: Self.v2Key, id: id)
    #expect(pickedAgain.selectedApp == Self.sampleKey)
    #expect(pickedAgain.selectedVersionID == nil)
    #expect(!pickedAgain.canInstall)

    // (d) 자동으로 고른 뒤 거듭 새로 고침: 마지막 받기 결과에서 다시 고른다.
    var twice = try Self.loaded()
    _ = Self.refresh(&twice)
    twice.appSelected(Self.sampleKey)
    id = Self.refresh(&twice)
    twice.loaded(.success(olderOnly), for: Self.v2Key, id: id)
    #expect(twice.selectedVersionID == AndroidCatalogData.older)

    // (e) 읽힌 구역에서 고른 뒤 새로 고침: 기존처럼 고른 버전이 없으면 버전 선택만 비운다.
    var settled = try Self.loaded()
    settled.appSelected(Self.sampleKey)
    #expect(settled.selectedVersionID == AndroidCatalogData.newest)
    id = Self.refresh(&settled)
    settled.loaded(.success(olderOnly), for: Self.v2Key, id: id)
    #expect(settled.selectedApp == Self.sampleKey)
    #expect(settled.selectedVersionID == nil)
  }

  @Test("다시 받기가 실패한 구역은 앞 목록을 지우고 실패 이유를 보이며, 그 구역 선택을 비운다")
  func reloadFailureClearsList() throws {
    var draft = try Self.loaded()
    let id = Self.refresh(&draft)
    draft.appSelected(Self.sampleKey)

    draft.loaded(.failure(.download(.offline)), for: Self.v2Key, id: id)
    #expect(draft.sources[0].state == .failed(.download(.offline)))
    #expect(draft.appRows(in: draft.sources[0]).isEmpty)
    #expect(draft.note(for: draft.sources[0]) == .failed(.download(.offline), isLocked: false))
    #expect(draft.selectedApp == nil)
    #expect(draft.versionPane == .noSelection)
    #expect(!draft.canInstall)
  }

  @Test("다른 구역이 아직 다시 읽는 중이어도 결과가 온 구역의 고른 버전은 설치할 수 있다")
  func otherSourceSettledWhileReloading() throws {
    let urls = [AndroidCatalogData.v2Raw, AndroidCatalogData.qaRaw]
    let v2Catalog = try AndroidCatalogData.catalog(AndroidCatalogData.v2JSON)
    let qaCatalog = try AndroidCatalogData.catalog(AndroidCatalogData.qaJSON)
    var draft = Self.draft()
    var id = Self.refresh(&draft, urls: urls)
    draft.loaded(.success(v2Catalog), for: Self.v2Key, id: id)
    draft.loaded(.success(qaCatalog), for: Self.qaKey, id: id)

    id = Self.refresh(&draft, urls: urls)
    draft.loaded(.success(v2Catalog), for: Self.v2Key, id: id)
    draft.appSelected(Self.sampleKey)
    #expect(draft.canInstall)
    draft.appSelected(Self.qaSampleKey)
    #expect(draft.selectedApp == Self.qaSampleKey)
    #expect(!draft.canInstall)
    #expect(draft.isLoading)

    draft.loaded(.success(qaCatalog), for: Self.qaKey, id: id)
    #expect(!draft.isLoading)
    #expect(draft.canInstall)
  }

  @Test("앱 줄 id 는 카탈로그와 앱 id 의 쌍이라 카탈로그 사이에 같은 앱 id 가 있어도 모든 줄 id 가 다르고, 고르면 그 줄 카탈로그의 버전·빌드 주소가 나온다")
  func appRowsUniqueAcrossCatalogs() throws {
    var draft = Self.draft()
    let id = Self.refresh(&draft, urls: [
      AndroidCatalogData.v2Raw,
      AndroidCatalogData.qaRaw,
      AndroidCatalogData.iOSOnlyRaw,
      "http://x.example.com/c.json",
      AndroidCatalogData.emptyRaw,
    ])
    try draft.loaded(.success(AndroidCatalogData.catalog(AndroidCatalogData.v2JSON)), for: Self.v2Key, id: id)
    try draft.loaded(.success(AndroidCatalogData.catalog(AndroidCatalogData.qaJSON)), for: Self.qaKey, id: id)
    draft.loaded(.failure(.download(.httpStatus(404))), for: AndroidCatalogData.iOSOnly.comparisonKey, id: id)

    let rows = draft.sources.flatMap { draft.appRows(in: $0) }
    #expect(Set(rows.map(\.id)).count == rows.count)
    #expect(rows.map(\.name) == ["Sample (Android)", "Empty", "Sample (QA)"])
    // v2 구역은 같은 id 의 iOS·Android 앱 중 Android 한 줄만.
    #expect(draft.appRows(in: draft.sources[0]).map(\.id) == [Self.sampleKey, Self.emptyAppKey])
    // 실패·쓸 수 없는 주소·읽는 중 구역은 줄이 없다.
    #expect(draft.sources[2...].allSatisfy { draft.appRows(in: $0).isEmpty })

    draft.appSelected(Self.sampleKey)
    #expect(draft.selectedVersion?.buildURL == AndroidCatalogData.newestURL)
    draft.appSelected(Self.qaSampleKey)
    #expect(draft.selectedAppValue?.name == "Sample (QA)")
    #expect(draft.selectedVersion?.buildURL == AndroidCatalogData.qaBuildURL)
  }
}

/// Draft 테스트의 추가 주소와 내용. qa 는 v2 와 같은 Android 앱 id 를 쓰는 다른 카탈로그다.
extension AndroidCatalogData {
  static let qaRaw = "https://cdn.example.org/qa/catalog.json"
  static let qaURL = DownloadURL(qaRaw)!
  static let qaVersion = BuildCatalog.VersionID("qa-44")
  static let qaBuildURL = DownloadURL("https://cdn.example.org/qa/Sample-QA-44.apk")!
  /// 새로 등록한 카탈로그 (앞 결과 없음).
  static let newRaw = "https://cdn.example.org/new/catalog.json"

  static func catalog(_ data: Data) throws -> BuildCatalog {
    try BuildCatalog(jsonData: data)
  }

  static let qaJSON = Data("""
  {
    "schemaVersion": 2,
    "apps": [
      {
        "id": "com.example.sample", "name": "Sample (QA)", "platform": "android",
        "versions": [{ "id": "qa-44", "name": "1.4.0 QA (44)", "branch": "release/1.4", "buildNumber": "44",
                       "createdAt": "2026-10-23T02:00:00Z",
                       "buildURL": "https://cdn.example.org/qa/Sample-QA-44.apk" }]
      }
    ]
  }
  """.utf8)

  /// 앱이 하나도 없는 v2.
  static let emptyJSON = Data(#"{ "schemaVersion": 2, "apps": [] }"#.utf8)

  /// android-43 이 사라지고 android-42 만 남은 v2 (가장 새 버전이 바뀐다).
  static let olderOnlyJSON = Data("""
  {
    "schemaVersion": 2,
    "apps": [
      {
        "id": "com.example.sample", "name": "Sample (Android)", "platform": "android",
        "versions": [{ "id": "android-42", "name": "1.3.0 (42)", "createdAt": "2026-10-21T04:08:49Z",
                       "buildURL": "https://builds.example.com/Sample-42.apk" }]
      }
    ]
  }
  """.utf8)

  /// Android 앱은 남았지만 버전이 없는 v2.
  static let sampleWithoutVersionsJSON = Data("""
  {
    "schemaVersion": 2,
    "apps": [{ "id": "com.example.sample", "name": "Sample (Android)", "platform": "android", "versions": [] }]
  }
  """.utf8)
}
