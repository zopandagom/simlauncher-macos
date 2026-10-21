import Core
import DownloadInterface
import Foundation
import Synchronization
import Testing
@testable import DownloadImpl

/// 테스트마다 만드는 임시 폴더. Impl 의 `temporaryDirectory` 로 넘기고, 끝나면 `remove()` 로 지운다.
struct TemporaryDirectory {
  /// 실제 경로 (`/var` → `/private/var`). Impl 이 돌려주는 경로와 같은 형식이다
  /// (`resolvingSymlinksInPath()` 는 `/private` 를 다시 떼어 쓰지 않는다).
  let url: URL

  init() throws {
    let base = FileManager.default.temporaryDirectory.appending(path: "DownloadTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    self.url = try URL(filePath: #require(RealPath.of(base)), directoryHint: .isDirectory)
  }

  func remove() {
    try? FileManager.default.removeItem(at: self.url)
  }

  /// 안에 있는 항목 이름 (정렬).
  var names: [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: self.url.path(percentEncoded: false))) ?? []).sorted()
  }

  /// 스텁으로만 요청하는 Impl. 여유는 넉넉하게, 시계는 멈춘 시계(받는 중 진행 값이 나오지 않는다)가 기본이다.
  func client(
    availableCapacity: @escaping @Sendable (URL) -> Int64? = { _ in 1_000_000_000 },
    openSink: @escaping @Sendable (URL) throws -> any FileSink = FileHandleSink.create,
    now: @escaping @Sendable () -> ContinuousClock.Instant = Clocks.stopped()
  ) -> DownloadClientImpl {
    DownloadClientImpl(
      temporaryDirectory: self.url,
      availableCapacity: availableCapacity,
      openSink: openSink,
      protocolClasses: [StubURLProtocol.self],
      now: now
    )
  }
}

/// Impl 에 넣는 시계.
enum Clocks {
  /// 늘 같은 시각. 스로틀 때문에 받는 중 진행 값은 넘어가지 않는다.
  static func stopped() -> @Sendable () -> ContinuousClock.Instant {
    let instant = ContinuousClock.now
    return { instant }
  }

  /// 부를 때마다 `step` 씩 간다.
  static func stepping(by step: Duration = .milliseconds(100)) -> @Sendable () -> ContinuousClock.Instant {
    let current = Mutex(ContinuousClock.now)
    return {
      current.withLock { instant in
        instant = instant.advanced(by: step)
        return instant
      }
    }
  }
}

/// 받은 진행 값 기록.
final class ProgressLog: Sendable {
  private let recorded = Mutex<[DownloadProgress]>([])

  var values: [DownloadProgress] {
    self.recorded.withLock { $0 }
  }

  func append(_ progress: DownloadProgress) {
    self.recorded.withLock { $0.append(progress) }
  }
}

/// 진행 값 줄임말: (받은 바이트, 전체).
func progress(_ received: Int64, _ expected: Int64?) -> DownloadProgress {
  DownloadProgress(receivedBytes: received, expectedBytes: expected)
}

/// n 번째 쓰기에서 오류를 던지는 파일 쓰기 (쓰기는 버린다).
final class FailingSink: FileSink {
  private let error: any Error
  private let failAt: Int
  private let writes = Mutex(0)

  init(error: any Error, failAt: Int = 1) {
    self.error = error
    self.failAt = failAt
  }

  func write(_: Data) throws {
    let count = self.writes.withLock { count in
      count += 1
      return count
    }
    if count >= self.failAt {
      throw self.error
    }
  }

  func close() {}
}

/// 실제 네트워크 없이 응답을 흉내 내는 URLProtocol. 시나리오를 **호스트 이름**으로 찾으므로 테스트마다
/// `register(_:)` 가 만든 `t-<UUID>.test` 호스트를 쓴다 (병렬 실행에서 섞이지 않는다).
/// fail-closed: 등록되지 않은 호스트의 요청은 `URLError(.unsupportedURL)` 로 끝내고 `unregisteredRequests` 에 남긴다.
/// client 호출은 모두 `startLoading` 안에서 동기로 한다.
final class StubURLProtocol: URLProtocol {
  enum Scenario: Sendable {
    /// 응답 → 조각들 → `finish` 면 정상 종료. `finish` 가 false 면 끝내지 않는다 (취소해야 끝난다).
    case respond(status: Int, headers: [String: String], chunks: [Data], finish: Bool)
    /// 응답 없이 이 코드로 실패한다.
    case fail(URLError.Code)
    /// `location` 으로 리다이렉트한다.
    case redirect(location: URL, status: Int)
  }

  private struct Registry {
    var scenarios: [String: Scenario] = [:]
    var starts: [String: Int] = [:]
    var stops: [String: Int] = [:]
    var unregistered: [URL] = []
  }

  private static let registry = Mutex(Registry())

  /// 새 호스트에 시나리오를 등록하고 `<scheme>://<host>/file.zip` 을 돌려준다.
  static func register(_ scenario: Scenario, scheme: String = "https") -> URL {
    let host = "t-\(UUID().uuidString.lowercased()).test"
    self.registry.withLock { $0.scenarios[host] = scenario }
    return URL(string: "\(scheme)://\(host)/file.zip")!
  }

  /// `register(_:)` 와 같고 `DownloadURL` 로 돌려준다 (https 만).
  static func registerDownload(_ scenario: Scenario) -> DownloadURL {
    DownloadURL(self.register(scenario).absoluteString)!
  }

  /// 그 호스트에서 `startLoading` 이 불린 횟수.
  static func startCount(_ url: URL) -> Int {
    self.registry.withLock { $0.starts[url.host() ?? "", default: 0] }
  }

  /// 그 호스트에서 `stopLoading` 이 불린 횟수.
  static func stopCount(_ url: URL) -> Int {
    self.registry.withLock { $0.stops[url.host() ?? "", default: 0] }
  }

  /// 등록되지 않은 호스트로 간 요청 (모든 테스트 합).
  static var unregisteredRequests: [URL] {
    self.registry.withLock { $0.unregistered }
  }

  /// Impl 테스트마다 끝에 본다. 전역이라 다른 테스트의 누수가 보일 수 있어 URL(호스트로 테스트를 찾는다)을 메시지에 넣는다.
  static func expectNoUnregisteredRequests(sourceLocation: SourceLocation = #_sourceLocation) {
    let urls = self.unregisteredRequests
    #expect(urls.isEmpty, "등록 안 된 요청: \(urls)", sourceLocation: sourceLocation)
  }

  override static func canInit(with _: URLRequest) -> Bool {
    true
  }

  override static func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let client = self.client, let url = self.request.url else {
      return
    }
    let host = url.host() ?? ""
    let scenario: Scenario? = Self.registry.withLock { registry in
      guard let scenario = registry.scenarios[host] else {
        registry.unregistered.append(url)
        return nil
      }
      registry.starts[host, default: 0] += 1
      return scenario
    }
    switch scenario {
    case .none:
      client.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
    case let .respond(status, headers, chunks, finish):
      let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
      client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      for chunk in chunks {
        client.urlProtocol(self, didLoad: chunk)
      }
      if finish {
        client.urlProtocolDidFinishLoading(self)
      }
    case let .fail(code):
      client.urlProtocol(self, didFailWithError: URLError(code))
    case let .redirect(location, status):
      let response = HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: ["Location": location.absoluteString]
      )!
      client.urlProtocol(self, wasRedirectedTo: URLRequest(url: location), redirectResponse: response)
    }
  }

  override func stopLoading() {
    let host = self.request.url?.host() ?? ""
    Self.registry.withLock { $0.stops[host, default: 0] += 1 }
  }
}

/// 조건이 참이 될 때까지 10ms 마다 본다. 10초가 지나면 실패.
func waitUntil(_ condition: () -> Bool) async throws {
  let deadline = ContinuousClock.now + .seconds(10)
  while !condition() {
    guard ContinuousClock.now < deadline else {
      Issue.record("10초 안에 조건이 참이 되지 않았다")
      throw CancellationError()
    }
    try await Task.sleep(for: .milliseconds(10))
  }
}

/// 링크를 따라가지 않은 권한 비트.
func mode(_ url: URL) -> mode_t? {
  var info = stat()
  guard lstat(url.path(percentEncoded: false), &info) == 0 else {
    return nil
  }
  return info.st_mode & 0o7777
}
