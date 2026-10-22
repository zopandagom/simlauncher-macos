import Core
import DownloadInterface
import DownloadTesting
import Foundation
import PreferencesInterface
import PreferencesTesting
import Synchronization
import Testing
@testable import SettingsFeature

/// Settings Model 테스트가 함께 쓰는 도움 함수. 테스트 타입이 채택하면 `Self.openedModel()` 처럼 부른다.
@MainActor
protocol SettingsModelTesting {}

@MainActor
extension SettingsModelTesting {
  /// 창을 연(`onAppear`) Model. 받기 Client 는 넘긴 것(기본: 앱 2개 카탈로그를 돌려주는 Fake)을 쓴다.
  static func openedModel(
    preferences: PreferencesClientFake = PreferencesClientFake(),
    download: any DownloadClient = Self.catalogFake()
  ) -> SettingsModel {
    let model = SettingsModel(preferences: preferences, download: download)
    model.onAppear()
    return model
  }

  /// `fetchData` 가 앱 2개 카탈로그를 돌려주는 Fake.
  static func catalogFake() -> DownloadClientFake {
    let fake = DownloadClientFake()
    fake.setFetchResult(.success(CatalogData.twoApps))
    return fake
  }

  static func url(_ raw: String) -> DownloadURL {
    DownloadURL(raw)!
  }

  /// `addCatalogURL` 호출 수.
  static func addCount(_ preferences: PreferencesClientFake) -> Int {
    preferences.calls.filter {
      if case .addCatalogURL = $0 {
        true
      } else {
        false
      }
    }.count
  }

  /// `removeCatalogURL` 호출 수.
  static func removeCount(_ preferences: PreferencesClientFake) -> Int {
    preferences.calls.filter {
      if case .removeCatalogURL = $0 {
        true
      } else {
        false
      }
    }.count
  }

  /// `fetchData` 호출 수.
  static func fetchCount(_ download: DownloadClientFake) -> Int {
    download.calls.filter {
      if case .fetchData = $0 {
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

  /// 끝났는지 `waitUntil` 조건에서 볼 수 있게 작업을 띄운다. 회귀가 있으면 멈출 수 있는 호출(멈춘 받기를 기다리는 등록)을
  /// 직접 await 하지 않고 이것으로 띄운다.
  static func start(_ operation: @escaping @MainActor () async -> Void) -> TrackedTask {
    TrackedTask(operation)
  }
}

/// 기다리는 조건은 Fake 와 MainActor 의 차례 넘기기(카탈로그 해석은 메인 밖)만으로 참이 되어 정상이면 수 ms 안에 끝난다.
/// 느린 CI 에서 거짓 실패가 나지 않게 10초로 둔다.
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

/// 테스트용 카탈로그 본문.
enum CatalogData {
  /// 앱 2개 (버전 하나, 버전 없음).
  static let twoApps = Data(
    """
    {"schemaVersion":1,"apps":[
      {"id":"app-a","name":"App A","versions":[
        {"id":"v1","name":"1.0","createdAt":"2026-10-21T04:08:49Z","buildURL":"https://example.com/a.zip"}
      ]},
      {"id":"app-b","name":"App B","versions":[]}
    ]}
    """.utf8
  )

  /// 로그인 페이지 같은 HTML.
  static let loginHTML = Data("<!doctype html><html><body>로그인</body></html>".utf8)

  /// 이 앱보다 새 규격.
  static let newerSchema = Data(#"{"schemaVersion":2,"apps":[]}"#.utf8)

  /// 2번째 앱의 1번째 버전에 createdAt 이 없다.
  static let missingCreatedAt = Data(
    """
    {"schemaVersion":1,"apps":[
      {"id":"app-a","name":"App A","versions":[]},
      {"id":"app-b","name":"App B","versions":[
        {"id":"v1","name":"1.0","buildURL":"https://example.com/b.zip"}
      ]}
    ]}
    """.utf8
  )
}

/// `fetchData` 호출마다 문을 만들어 테스트가 `release(call:with:)` 로 결과를 줄 때까지 기다리고, **Task 취소를 무시하고**
/// 그 결과를 돌려준다 (취소가 받기 끝과 겹쳐 받기가 성공·실패로 돌아오는 늦은 결과 흉내). 나머지 메서드는 Fake 에 넘긴다.
/// Fake 는 취소되면 늘 `.cancelled` 를 던지므로 늦은 결과를 만들 수 없어 둔다.
final class LateFetchDownloadClient: DownloadClient {
  private struct State {
    var callCount = 0
    var waiting: [Int: CheckedContinuation<Result<Data, DownloadError>, Never>] = [:]
    /// 호출이 문에 닿기 전에 준 결과.
    var released: [Int: Result<Data, DownloadError>] = [:]
  }

  private let fake = DownloadClientFake()
  private let state = Mutex(State())

  /// 들어온 `fetchData` 수.
  var fetchCount: Int {
    self.state.withLock { $0.callCount }
  }

  /// `call` 번째(1부터) `fetchData` 를 `result` 로 끝낸다.
  func release(call: Int, with result: Result<Data, DownloadError>) {
    let waiting: CheckedContinuation<Result<Data, DownloadError>, Never>? = self.state.withLock { state in
      guard let continuation = state.waiting.removeValue(forKey: call) else {
        state.released[call] = result
        return nil
      }
      return continuation
    }
    waiting?.resume(returning: result)
  }

  func fetchData(_: DownloadURL, maxBytes _: Int) async throws(DownloadError) -> Data {
    let call = self.state.withLock { state in
      state.callCount += 1
      return state.callCount
    }
    let result = await withCheckedContinuation { (continuation: CheckedContinuation<
      Result<Data, DownloadError>,
      Never
    >) in
      let ready: Result<Data, DownloadError>? = self.state.withLock { state in
        guard let released = state.released.removeValue(forKey: call) else {
          state.waiting[call] = continuation
          return nil
        }
        return released
      }
      if let ready {
        continuation.resume(returning: ready)
      }
    }
    return try result.get()
  }

  func download(
    _ url: DownloadURL,
    onProgress: @escaping @Sendable (DownloadProgress) async -> Void
  ) async throws(DownloadError) -> DownloadedFile {
    try await self.fake.download(url, onProgress: onProgress)
  }

  func removeDownloaded(_ file: DownloadedFile) async {
    await self.fake.removeDownloaded(file)
  }

  func removeLeftoverDownloads() async {
    await self.fake.removeLeftoverDownloads()
  }
}
