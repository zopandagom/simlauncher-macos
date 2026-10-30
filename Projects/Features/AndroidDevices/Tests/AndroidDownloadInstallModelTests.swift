import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import DownloadInterface
import DownloadTesting
import Foundation
import PreferencesTesting
import Testing
@testable import AndroidDevicesFeature

/// "URL 에서…"·"카탈로그에서…" 시트 Model. 설치 요청은 주입한 `installRequested` 로 기록만 한다.
@MainActor
struct AndroidDownloadInstallModelTests: AndroidDevicesTesting {
  static let tablet = AndroidVirtualDevice.bootedTabletSample
  static let label = AndroidDeviceLabel(.bootedTabletSample)

  // MARK: - URL 시트

  @Test("URL 시트는 켜진·쓸 수 있는 기기에만, 두 시트가 모두 닫혀 있을 때만 열린다")
  func urlMenuGuards() async {
    let model = Self.model()
    model.urlMenuTapped([.phoneSample])
    model.urlMenuTapped([.unsupportedNameSample])
    #expect(model.urlDraft == nil)
    await model.catalogMenuTapped([Self.tablet])
    model.urlMenuTapped([Self.tablet])
    #expect(model.urlDraft == nil)
    model.catalogCancelTapped()
    model.urlMenuTapped([Self.tablet])
    #expect(model.urlDraft?.targets == [AndroidTargetDevice(id: Self.tablet.id, label: Self.label)])
    await model.catalogMenuTapped([Self.tablet])
    #expect(model.catalogDraft == nil)
  }

  @Test("주소 문제가 있으면 설치를 눌러도 열린 채 요청하지 않고, 맞으면 닫고 입력한 주소로 한 번 요청한다")
  func urlInstall() async throws {
    let (model, requests) = Self.requestsSetup()
    model.urlMenuTapped([Self.tablet])
    model.urlTextChanged("http://builds.example.com/app.apk")
    #expect(model.urlDraft?.problem != nil)
    #expect(model.urlDraft?.canSubmit == false)
    await model.urlInstallTapped()
    #expect(model.urlDraft != nil)
    #expect(requests.items.isEmpty)

    model.urlTextChanged("  https://builds.example.com/app.apk ")
    #expect(model.urlDraft?.problem == nil)
    #expect(model.urlDraft?.canSubmit == true)
    await model.urlInstallTapped()
    await model.urlInstallTapped()
    #expect(model.urlDraft == nil)
    #expect(try requests.items == [AndroidDownloadInstallRequest(
      deviceID: Self.tablet.id,
      device: Self.label,
      url: #require(DownloadURL("https://builds.example.com/app.apk")),
      origin: .enteredURL
    )])
  }

  @Test("URL 시트의 취소·바깥 닫기는 초안을 지운다 (두 번 불려도 무해하다)")
  func urlClose() {
    let model = Self.model()
    model.urlMenuTapped([Self.tablet])
    model.urlCancelTapped()
    #expect(model.urlDraft == nil)
    model.urlMenuTapped([Self.tablet])
    model.urlSheetDismissed()
    model.urlSheetDismissed()
    #expect(model.urlDraft == nil)
  }

  // MARK: - 카탈로그 시트

  @Test("열면 등록 카탈로그를 모두 받아 구역마다 Android 앱만 보이고, 비면 이유를 고른다")
  func catalogSectionsAndReasons() async throws {
    let download = AndroidCatalogData.fake()
    let model = Self.model(
      urls: [
        AndroidCatalogData.v2Raw,
        AndroidCatalogData.v1Raw,
        AndroidCatalogData.iOSOnlyRaw,
        AndroidCatalogData.emptyRaw,
      ],
      download: download
    )
    model.urlMenuTapped([.phoneSample])
    await model.catalogMenuTapped([Self.tablet])
    let draft = try #require(model.catalogDraft)
    #expect(draft.targets == [AndroidTargetDevice(id: Self.tablet.id, label: Self.label)])
    #expect(draft.sources.count == 4)
    #expect(draft.apps(in: draft.sources[0]).map(\.name) == ["Sample (Android)", "Empty"])
    #expect(draft.apps(in: draft.sources[0]).allSatisfy { $0.platform == .android })
    #expect(draft.emptyReason(for: draft.sources[0]) == nil)
    #expect(draft.emptyReason(for: draft.sources[1]) == .schemaVersion1)
    #expect(draft.emptyReason(for: draft.sources[2]) == .noAndroidApps)
    #expect(draft.emptyReason(for: draft.sources[3]) == .noApps)
    #expect(draft.apps(in: draft.sources[1]).isEmpty)
    #expect(!draft.isLoading)
    #expect(draft.versionPane == .noSelection)
  }

  @Test("받지 못한 카탈로그·형식 문제·쓸 수 없는 주소는 그 구역에만 이유가 있고, 잠김을 함께 담는다")
  func catalogNotes() async throws {
    for isLocked in [false, true] {
      let download = AndroidCatalogData.fake()
      download.setFetchResult(.failure(.httpStatus(404)), for: AndroidCatalogData.iOSOnly)
      download.setFetchResult(.success(AndroidCatalogData.badPlatformJSON), for: AndroidCatalogData.empty)
      let model = Self.model(
        urls: [
          AndroidCatalogData.v2Raw,
          AndroidCatalogData.iOSOnlyRaw,
          AndroidCatalogData.emptyRaw,
          "http://x.example.com/c.json",
        ],
        isLocked: isLocked,
        download: download
      )
      await model.catalogMenuTapped([Self.tablet])
      let draft = try #require(model.catalogDraft)
      #expect(draft.isLocked == isLocked)
      #expect(draft.note(for: draft.sources[0]) == nil)
      #expect(draft.note(for: draft.sources[1]) == .failed(.download(.httpStatus(404)), isLocked: isLocked))
      guard case .failed(.catalog, isLocked) = draft.note(for: draft.sources[2]) else {
        Issue.record("형식 문제 구역이 아니다: \(String(describing: draft.note(for: draft.sources[2])))")
        return
      }
      guard case .invalid(_, isLocked) = draft.note(for: draft.sources[3]) else {
        Issue.record("쓸 수 없는 주소 구역이 아니다: \(String(describing: draft.note(for: draft.sources[3])))")
        return
      }
      #expect(draft.emptyReason(for: draft.sources[1]) == nil)
    }
  }

  @Test("등록이 없으면 빈 목록이고, 잠기지 않았을 때만 설정 열기를 보인다")
  func catalogEmpty() async {
    for isLocked in [false, true] {
      let model = Self.model(isLocked: isLocked)
      await model.catalogMenuTapped([Self.tablet])
      #expect(model.catalogDraft?.isEmpty == true)
      #expect(model.catalogDraft?.showsOpenSettings == !isLocked)
    }
  }

  @Test("Android 앱을 고르면 가장 새 버전이 골라지고, 같은 id 의 iOS 앱이 아니라 Android 앱이다. iOS 앱 id 는 고를 수 없다")
  func catalogSelection() async throws {
    let download = AndroidCatalogData.fake()
    let model = Self.model(urls: [AndroidCatalogData.v2Raw, AndroidCatalogData.iOSOnlyRaw], download: download)
    await model.catalogMenuTapped([Self.tablet])
    let sourceID = try #require(model.catalogDraft?.sources.first?.id)
    model.catalogAppSelected(AndroidCatalogAppKey(sourceID: sourceID, appID: AndroidCatalogData.sampleID))
    #expect(model.catalogDraft?.selectedAppValue?.name == "Sample (Android)")
    #expect(model.catalogDraft?.selectedVersion?.id == AndroidCatalogData.newest)
    model.catalogVersionSelected(AndroidCatalogData.older)
    #expect(model.catalogDraft?.selectedVersionID == AndroidCatalogData.older)
    model.catalogVersionSelected(AndroidCatalogData.iOSVersion)
    #expect(model.catalogDraft?.selectedVersionID == AndroidCatalogData.older)

    let iOSSource = try #require(model.catalogDraft?.sources.last?.id)
    model.catalogAppSelected(AndroidCatalogAppKey(sourceID: iOSSource, appID: AndroidCatalogData.toolID))
    #expect(model.catalogDraft?.selectedApp == nil)
    #expect(model.catalogDraft?.selectedVersionID == nil)
    #expect(model.catalogDraft?.canInstall == false)
  }

  @Test("새로 고침: 고른 앱·버전이 그대로면 유지하고, 버전만 사라지면 버전만, 앱이 Android 가 아니게 되면 선택을 비운다")
  func catalogRefreshKeepsSelection() async throws {
    let download = AndroidCatalogData.fake()
    let model = Self.model(urls: [AndroidCatalogData.v2Raw], download: download)
    await model.catalogMenuTapped([Self.tablet])
    let sourceID = try #require(model.catalogDraft?.sources.first?.id)
    let key = AndroidCatalogAppKey(sourceID: sourceID, appID: AndroidCatalogData.sampleID)
    model.catalogAppSelected(key)
    model.catalogVersionSelected(AndroidCatalogData.older)

    await model.catalogRefreshTapped()
    #expect(model.catalogDraft?.selectedApp == key)
    #expect(model.catalogDraft?.selectedVersionID == AndroidCatalogData.older)

    download.setFetchResult(.success(AndroidCatalogData.newestOnlyJSON), for: AndroidCatalogData.catalogV2)
    await model.catalogRefreshTapped()
    #expect(model.catalogDraft?.selectedApp == key)
    #expect(model.catalogDraft?.selectedVersionID == nil)

    model.catalogVersionSelected(AndroidCatalogData.newest)
    download.setFetchResult(
      .success(AndroidCatalogData.iOSOnlyJSON(id: "com.example.sample")),
      for: AndroidCatalogData.catalogV2
    )
    await model.catalogRefreshTapped()
    #expect(model.catalogDraft?.selectedApp == nil)
    #expect(model.catalogDraft?.selectedVersionID == nil)
  }

  @Test("새로 고침에서 그 카탈로그가 실패하거나 설정에서 지워지면 선택을 비운다")
  func catalogRefreshClearsOnFailureOrRemoval() async throws {
    let download = AndroidCatalogData.fake()
    let (model, preferences) = Self.preferencesSetup(urls: [AndroidCatalogData.v2Raw], download: download)
    await model.catalogMenuTapped([Self.tablet])
    let sourceID = try #require(model.catalogDraft?.sources.first?.id)
    let key = AndroidCatalogAppKey(sourceID: sourceID, appID: AndroidCatalogData.sampleID)
    model.catalogAppSelected(key)
    download.setFetchResult(.failure(.offline), for: AndroidCatalogData.catalogV2)
    await model.catalogRefreshTapped()
    #expect(model.catalogDraft?.selectedApp == nil)

    download.setFetchResult(.success(AndroidCatalogData.v2JSON), for: AndroidCatalogData.catalogV2)
    await model.catalogRefreshTapped()
    model.catalogAppSelected(key)
    #expect(model.catalogDraft?.selectedApp == key)
    preferences.setStored(urls: [AndroidCatalogData.iOSOnlyRaw], isLocked: false)
    await model.catalogRefreshTapped()
    #expect(model.catalogDraft?.selectedApp == nil)
  }

  @Test("받는 중 닫으면 받기가 취소되고, 늦은 결과는 다시 연 시트에 들어가지 않는다")
  func catalogCloseWhileLoading() async {
    let download = AndroidCatalogData.fake()
    download.suspendFetches(for: AndroidCatalogData.catalogV2)
    let model = Self.model(urls: [AndroidCatalogData.v2Raw], download: download)
    let open = Self.start { await model.catalogMenuTapped([Self.tablet]) }
    await Self.waitUntil { download.suspendedFetchCount == 1 }
    #expect(model.catalogDraft?.isLoading == true)
    model.catalogSheetDismissed()
    await Self.waitUntil { open.isFinished }
    #expect(model.catalogDraft == nil)
    model.catalogSheetDismissed()
    download.resumeFetches()
  }

  @Test("받아서 설치는 고른 버전이 있을 때만, 첫 await 전에 닫고 그 버전의 빌드 주소로 한 번 요청한다")
  func catalogInstall() async throws {
    let download = AndroidCatalogData.fake()
    let (model, requests) = Self.requestsSetup(urls: [AndroidCatalogData.v2Raw], download: download)
    await model.catalogMenuTapped([Self.tablet])
    await model.catalogInstallTapped()
    #expect(model.catalogDraft != nil)
    #expect(requests.items.isEmpty)

    let sourceID = try #require(model.catalogDraft?.sources.first?.id)
    model.catalogAppSelected(AndroidCatalogAppKey(sourceID: sourceID, appID: AndroidCatalogData.sampleID))
    await model.catalogInstallTapped()
    await model.catalogInstallTapped()
    #expect(model.catalogDraft == nil)
    #expect(requests.items == [AndroidDownloadInstallRequest(
      deviceID: Self.tablet.id,
      device: Self.label,
      url: AndroidCatalogData.newestURL,
      origin: .catalog
    )])
  }

  @Test("고른 앱의 카탈로그를 다시 읽는 중이면 버전 칸이 읽는 중이고 설치할 수 없다")
  func versionPaneWhileReloading() async throws {
    let download = AndroidCatalogData.fake()
    let model = Self.model(urls: [AndroidCatalogData.v2Raw], download: download)
    await model.catalogMenuTapped([Self.tablet])
    let sourceID = try #require(model.catalogDraft?.sources.first?.id)
    model.catalogAppSelected(AndroidCatalogAppKey(sourceID: sourceID, appID: AndroidCatalogData.emptyAppID))
    #expect(model.catalogDraft?.versionPane == .noVersions)
    model.catalogAppSelected(AndroidCatalogAppKey(sourceID: sourceID, appID: AndroidCatalogData.sampleID))
    download.suspendFetches(for: AndroidCatalogData.catalogV2)
    let refresh = Self.start { await model.catalogRefreshTapped() }
    await Self.waitUntil { download.suspendedFetchCount == 1 }
    #expect(model.catalogDraft?.versionPane == .loading)
    #expect(model.catalogDraft?.canInstall == false)
    download.resumeFetches()
    await Self.waitUntil { refresh.isFinished }
    #expect(model.catalogDraft?.canInstall == true)
  }
}

extension AndroidDownloadInstallModelTests {
  /// 설치 요청 기록.
  @MainActor
  final class Requests {
    private(set) var items: [AndroidDownloadInstallRequest] = []

    func append(_ request: AndroidDownloadInstallRequest) {
      self.items.append(request)
    }
  }

  struct Setup {
    let model: AndroidDownloadInstallModel
    let requests: Requests
    let preferences: PreferencesClientFake
  }

  static func setup(
    urls: [String] = [],
    isLocked: Bool = false,
    download: DownloadClientFake = DownloadClientFake()
  ) -> Setup {
    let requests = Requests()
    let preferences = PreferencesClientFake(urls: urls, isLocked: isLocked)
    let model = AndroidDownloadInstallModel(
      preferences: preferences,
      download: download,
      installRequested: { requests.append($0) }
    )
    return Setup(model: model, requests: requests, preferences: preferences)
  }

  static func model(
    urls: [String] = [],
    isLocked: Bool = false,
    download: DownloadClientFake = DownloadClientFake()
  ) -> AndroidDownloadInstallModel {
    self.setup(urls: urls, isLocked: isLocked, download: download).model
  }

  static func requestsSetup(
    urls: [String] = [],
    download: DownloadClientFake = DownloadClientFake()
  ) -> (AndroidDownloadInstallModel, Requests) {
    let setup = self.setup(urls: urls, download: download)
    return (setup.model, setup.requests)
  }

  static func preferencesSetup(
    urls: [String] = [],
    download: DownloadClientFake = DownloadClientFake()
  ) -> (AndroidDownloadInstallModel, PreferencesClientFake) {
    let setup = self.setup(urls: urls, download: download)
    return (setup.model, setup.preferences)
  }
}

/// 카탈로그 시트 테스트의 주소와 내용 (docs/CATALOG.md). v2 는 iOS·Android 앱이 같은 id 를 쓴다.
enum AndroidCatalogData {
  static let v2Raw = "https://builds.example.com/catalog.json"
  static let v1Raw = "https://builds.example.com/v1/catalog.json"
  static let iOSOnlyRaw = "https://cdn.example.org/ios/catalog.json"
  static let emptyRaw = "https://cdn.example.org/empty/catalog.json"
  static let catalogV2 = DownloadURL(v2Raw)!
  static let catalogV1 = DownloadURL(v1Raw)!
  static let iOSOnly = DownloadURL(iOSOnlyRaw)!
  static let empty = DownloadURL(emptyRaw)!
  static let sampleID = BuildCatalog.AppID("com.example.sample")
  static let toolID = BuildCatalog.AppID("com.example.tool")
  static let emptyAppID = BuildCatalog.AppID("com.example.empty")
  static let newest = BuildCatalog.VersionID("android-43")
  static let older = BuildCatalog.VersionID("android-42")
  static let iOSVersion = BuildCatalog.VersionID("ios-42")
  static let newestURL = DownloadURL("https://builds.example.com/Sample-43.apk")!

  /// 주소별 내용을 넣은 받기 Fake.
  static func fake() -> DownloadClientFake {
    let download = DownloadClientFake()
    download.setFetchResult(.success(self.v2JSON), for: self.catalogV2)
    download.setFetchResult(.success(self.v1JSON), for: self.catalogV1)
    download.setFetchResult(.success(self.iOSOnlyJSON(id: "com.example.tool")), for: self.iOSOnly)
    download.setFetchResult(.success(Data(#"{ "schemaVersion": 2, "apps": [] }"#.utf8)), for: self.empty)
    return download
  }

  static let v2JSON = Data("""
  {
    "schemaVersion": 2,
    "apps": [
      {
        "id": "com.example.sample", "name": "Sample (iOS)", "platform": "ios",
        "versions": [{ "id": "ios-42", "name": "1.3.0 (42)", "createdAt": "2026-10-21T04:08:49Z",
                       "buildURL": "https://builds.example.com/Sample-42.zip" }]
      },
      {
        "id": "com.example.sample", "name": "Sample (Android)", "platform": "android",
        "versions": [
          { "id": "android-42", "name": "1.3.0 (42)", "createdAt": "2026-10-21T04:08:49Z",
            "buildURL": "https://builds.example.com/Sample-42.apk" },
          { "id": "android-43", "name": "1.3.0 (43)", "createdAt": "2026-10-22T04:08:49Z",
            "buildURL": "https://builds.example.com/Sample-43.apk" }
        ]
      },
      { "id": "com.example.empty", "name": "Empty", "platform": "android", "versions": [] }
    ]
  }
  """.utf8)

  /// 새로 고침 뒤 android-42 가 사라진 v2.
  static let newestOnlyJSON = Data("""
  {
    "schemaVersion": 2,
    "apps": [
      {
        "id": "com.example.sample", "name": "Sample (Android)", "platform": "android",
        "versions": [{ "id": "android-43", "name": "1.3.0 (43)", "createdAt": "2026-10-22T04:08:49Z",
                       "buildURL": "https://builds.example.com/Sample-43.apk" }]
      }
    ]
  }
  """.utf8)

  /// v1 은 platform 을 적어도 무시해 모두 iOS 다.
  static let v1JSON = Data("""
  {
    "schemaVersion": 1,
    "apps": [{ "id": "com.example.sample", "name": "Sample", "platform": "android", "versions": [] }]
  }
  """.utf8)

  /// platform 대소문자가 틀린 v2 (`unsupportedPlatform`).
  static let badPlatformJSON = Data("""
  {
    "schemaVersion": 2,
    "apps": [{ "id": "com.example.sample", "name": "Sample", "platform": "Android", "versions": [] }]
  }
  """.utf8)

  /// iOS 앱 하나만 있는 v2.
  static func iOSOnlyJSON(id: String) -> Data {
    Data("""
    { "schemaVersion": 2, "apps": [{ "id": "\(id)", "name": "Tool", "platform": "ios", "versions": [] }] }
    """.utf8)
  }
}
