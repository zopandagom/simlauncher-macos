import AppBundleTesting
import Core
import DownloadInterface
import DownloadTesting
import Foundation
import PreferencesTesting
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

/// Launcher Model 테스트가 함께 쓰는 도움 함수. 테스트 타입이 채택하면 `Self.loadedModel()` 처럼 부른다.
@MainActor
protocol LauncherModelTesting {}

@MainActor
extension LauncherModelTesting {
  /// 샘플 목록 Fake 를 설정하고 첫 목록까지 읽은 Model. 앱 번들·받기 Client 는 넘긴 것(기본: 샘플 앱·샘플 받기 Fake)을 쓴다.
  static func loadedModel(
    appBundle: AppBundleClientFake = AppBundleClientFake(),
    download: any DownloadClient = DownloadClientFake(),
    _ configure: (SimulatorClientFake) -> Void = { _ in }
  ) async -> (LauncherModel, SimulatorClientFake) {
    let fake = SimulatorClientFake(inventory: .sample)
    configure(fake)
    let model = LauncherModel(simulator: fake, appBundle: appBundle, download: download)
    await model.onAppear()
    return (model, fake)
  }

  /// 샘플 목록에서 기기 하나의 상태만 바꾼 목록.
  static func inventory(_ id: VirtualDevice.ID, state: VirtualDevice.State) -> DeviceInventory {
    let sample = DeviceInventory.sample
    return DeviceInventory(
      devices: sample.devices.map { device in
        guard device.id == id else { return device }
        return VirtualDevice(
          id: device.id,
          name: device.name,
          family: device.family,
          state: state,
          availability: device.availability,
          runtime: device.runtime
        )
      },
      runtimes: sample.runtimes,
      deviceTypes: sample.deviceTypes
    )
  }

  /// 샘플 목록에서 기기 하나를 뺀 목록.
  static func inventory(removing id: VirtualDevice.ID) -> DeviceInventory {
    let sample = DeviceInventory.sample
    return DeviceInventory(
      devices: sample.devices.filter { $0.id != id },
      runtimes: sample.runtimes,
      deviceTypes: sample.deviceTypes
    )
  }

  /// 샘플 목록의 기기를 알림에 담을 값으로.
  static func label(_ id: VirtualDevice.ID) -> LauncherNotice.Device {
    let device = DeviceList(inventory: .sample).device(id: id)!
    return LauncherNotice.Device(name: device.name, runtimeName: device.runtime.name)
  }

  static func device(_ id: VirtualDevice.ID, in model: LauncherModel) -> VirtualDevice? {
    guard case let .loaded(list) = model.listState else { return nil }
    return list.device(id: id)
  }

  static func bootCount(_ id: VirtualDevice.ID, in fake: SimulatorClientFake) -> Int {
    fake.calls.filter { $0 == .boot(id) }.count
  }

  static func createCount(in fake: SimulatorClientFake) -> Int {
    fake.calls.filter {
      if case .create = $0 {
        true
      } else {
        false
      }
    }.count
  }

  /// 조건이 참이 될 때까지 다른 작업에 차례를 넘긴다. `waitLimit` 안에 참이 되지 않으면 호출 지점에 실패를 기록하고
  /// 돌아온다 (회귀가 있어도 테스트가 멈추지 않고 실패로 끝나게).
  static func waitUntil(
    _ condition: () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    let deadline = ContinuousClock.now + waitLimit
    while !condition() {
      guard ContinuousClock.now < deadline else {
        Issue.record("\(waitLimit) 안에 조건이 참이 되지 않았다", sourceLocation: sourceLocation)
        return
      }
      await Task.yield()
    }
  }

  /// 끝났는지 `waitUntil` 조건에서 볼 수 있게 작업을 띄운다. 회귀가 있으면 멈출 수 있는 호출(Fake 를 멈춘 동안의 두 번째
  /// 누름)을 직접 await 하지 않고 이것으로 띄운다.
  static func start(_ operation: @escaping @MainActor () async -> Void) -> TrackedTask {
    TrackedTask(operation)
  }
}

/// 기다리는 조건은 Fake 와 MainActor 의 차례 넘기기만으로 참이 되어, 정상이면 수 ms 안에 끝난다 (Launcher 스위트 전체가
/// 0.1초 안쪽). 느린 CI 에서 거짓 실패가 나지 않게 그 1000배 이상인 10초로 둔다.
private let waitLimit: Duration = .seconds(10)

/// 끝났는지 볼 수 있는 작업.
@MainActor
final class TrackedTask {
  private(set) var isFinished = false
  private var task: Task<Void, Never>?

  init(_ operation: @escaping @MainActor () async -> Void) {
    self.task = Task {
      await operation()
      self.isFinished = true
    }
  }

  /// 작업이 끝날 때까지 기다린다.
  func value() async {
    await self.task?.value
  }
}

// MARK: - 카탈로그에서 설치

/// 카탈로그에서 설치 시트 테스트가 함께 쓰는 도움 함수. `waitUntil`·`start` 는 `LauncherModelTesting` 것을 쓴다.
@MainActor
protocol CatalogInstallModelTesting: LauncherModelTesting {}

@MainActor
extension CatalogInstallModelTesting {
  /// 설치 요청을 `InstallRequests` 에 기록하는 Model. 기본 설정은 카탈로그 두 개, 받기는 둘 다 앱 2개 카탈로그다.
  static func catalogModel(
    preferences: PreferencesClientFake = PreferencesClientFake(urls: [CatalogData.firstRaw, CatalogData.secondRaw]),
    download: any DownloadClient = CatalogData.fake()
  ) -> (CatalogInstallModel, InstallRequests) {
    let requests = InstallRequests()
    let model = CatalogInstallModel(preferences: preferences, download: download) { request in
      await requests.record(request)
    }
    return (model, requests)
  }

  /// 샘플 목록의 기기.
  static func sampleDevice(_ id: VirtualDevice.ID) -> VirtualDevice {
    DeviceList(inventory: .sample).device(id: id)!
  }

  /// 샘플 목록에서 상태만 바꾼 기기.
  static func sampleDevice(_ id: VirtualDevice.ID, state: VirtualDevice.State) -> VirtualDevice {
    DeviceList(inventory: inventory(id, state: state)).device(id: id)!
  }

  /// 열린 시트의 구역 id 와 상태 (저장 순서).
  static func sourceStates(_ model: CatalogInstallModel) -> [CatalogSource.State] {
    model.draft?.sources.map(\.state) ?? []
  }

  /// `fetchData` 로 받은 주소 (호출 순서. 동시에 받으므로 순서는 보지 않는 쪽에서 Set 으로 비교한다).
  static func fetchedURLs(_ download: DownloadClientFake) -> [URL] {
    download.calls.compactMap {
      if case let .fetchData(url, _) = $0 {
        url
      } else {
        nil
      }
    }
  }
}

/// 설치 요청 기록. `suspend()` 뒤에는 `resume()` 까지 요청 호출이 돌아오지 않는다 (연타 테스트).
@MainActor
final class InstallRequests {
  private(set) var values: [CatalogInstallRequest] = []
  private var isSuspended = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  func suspend() {
    self.isSuspended = true
  }

  func resume() {
    self.isSuspended = false
    let waiting = self.waiting
    self.waiting = []
    for continuation in waiting {
      continuation.resume()
    }
  }

  func record(_ request: CatalogInstallRequest) async {
    self.values.append(request)
    guard self.isSuspended else { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      self.waiting.append(continuation)
    }
  }
}

/// 직접 만든 카탈로그 샘플 (docs/CATALOG.md 규격).
enum CatalogData {
  static let firstRaw = "https://builds.example.com/ios/catalog.json"
  static let secondRaw = "https://cdn.example.org/team/catalog.json"
  /// `firstRaw` 와 같은 카탈로그 (스킴·호스트 대소문자, 기본 포트).
  static let firstDuplicateRaw = "HTTPS://BUILDS.EXAMPLE.COM:443/ios/catalog.json"
  static let httpRaw = "http://builds.example.com/ios/catalog.json"
  static let first = DownloadURL(firstRaw)!
  static let second = DownloadURL(secondRaw)!
  static var firstKey: String {
    self.first.comparisonKey
  }

  static var secondKey: String {
    self.second.comparisonKey
  }

  static let alpha = BuildCatalog.AppID("alpha")
  static let beta = BuildCatalog.AppID("beta")
  /// alpha 의 버전 (v2 가 더 새롭다).
  static let alphaV1 = BuildCatalog.VersionID("v1")
  static let alphaV2 = BuildCatalog.VersionID("v2")
  static let betaV1 = BuildCatalog.VersionID("b1")
  static let alphaV2URL = DownloadURL("https://builds.example.com/alpha-2.zip")!

  private static let alphaV1JSON = """
  {"id":"v1","name":"1.0","createdAt":"2026-10-20T04:08:49Z","buildURL":"https://builds.example.com/alpha-1.zip"}
  """
  private static let alphaV2JSON = """
  {"id":"v2","name":"1.1","branch":"main","tag":"v1.1","buildNumber":"42",\
  "createdAt":"2026-10-21T04:08:49Z","buildURL":"https://builds.example.com/alpha-2.zip"}
  """
  private static let betaJSON = """
  {"id":"beta","name":"Beta","versions":[\
  {"id":"b1","name":"0.1","createdAt":"2026-10-19T00:00:00Z","buildURL":"https://builds.example.com/beta-1.zip"}]}
  """

  /// 앱 alpha(버전 v1·v2, 파일에는 v1 먼저)와 beta(버전 b1).
  static let twoApps = Data(
    [
      #"{"schemaVersion":1,"apps":[{"id":"alpha","name":"Alpha","versions":["#,
      alphaV1JSON, ",", alphaV2JSON, "]},", betaJSON, "]}",
    ].joined().utf8
  )
  /// alpha 에서 v2 가 사라진 카탈로그.
  static let alphaV1Only = Data(
    #"{"schemaVersion":1,"apps":[{"id":"alpha","name":"Alpha","versions":[\#(alphaV1JSON)]},\#(betaJSON)]}"#.utf8
  )
  /// alpha 가 사라진 카탈로그.
  static let betaOnly = Data(#"{"schemaVersion":1,"apps":[\#(betaJSON)]}"#.utf8)
  /// 버전이 없는 alpha.
  static let alphaWithoutVersions = Data(
    #"{"schemaVersion":1,"apps":[{"id":"alpha","name":"Alpha","versions":[]}]}"#.utf8
  )
  static let emptyApps = Data(#"{"schemaVersion":1,"apps":[]}"#.utf8)
  static let newerSchema = Data(#"{"schemaVersion":2,"apps":[]}"#.utf8)
  static let html = Data("<html><body>로그인</body></html>".utf8)

  /// 해석한 값.
  static func catalog(_ data: Data) throws -> BuildCatalog {
    try BuildCatalog(jsonData: data)
  }

  /// `fetchData` 가 모든 주소에 `data` 를 돌려주는 Fake.
  static func fake(_ data: Data = CatalogData.twoApps) -> DownloadClientFake {
    let fake = DownloadClientFake()
    fake.setFetchResult(.success(data))
    return fake
  }
}
