import Core
import DownloadInterface
import DownloadTesting
import Foundation
import Synchronization
import Testing

/// `DownloadClientFake.fetchData` 의 멈춤·재개·취소. 멈춤이 풀리지 않는 회귀에서도 테스트가 멈추지 않게, 끝나기는
/// `waitUntil`(10초 상한)로 기다린 뒤 정리로만 재개한다.
struct DownloadClientFakeFetchTests {
  static let url = DownloadURL("https://example.com/catalog.json")!
  static let otherURL = DownloadURL("https://example.org/other.json")!

  @Test("멈춘 fetch 는 기록된 뒤 기다리고, 재개하면 설정한 결과로 끝난다")
  func suspendAndResume() async throws {
    let fake = DownloadClientFake()
    fake.setFetchResult(.success(Data("{}".utf8)))
    fake.suspendFetches()
    let task = FetchTask(fake: fake, url: Self.url)

    try await waitUntil { fake.suspendedFetchCount == 1 }
    #expect(fake.calls == [.fetchData(Self.url.url, maxBytes: 10)])
    #expect(!task.isFinished)
    fake.resumeFetches()

    try await waitUntil { task.isFinished }
    #expect(task.result == .success(Data("{}".utf8)))
    #expect(fake.suspendedFetchCount == 0)
  }

  @Test("멈춘 동안 Task 가 취소되면 재개 없이 cancelled")
  func cancelWhileSuspended() async throws {
    let fake = DownloadClientFake()
    fake.suspendFetches()
    let task = FetchTask(fake: fake, url: Self.url)

    try await waitUntil { fake.suspendedFetchCount == 1 }
    task.cancel()

    let finished = await waitUntilOrTimeout { task.isFinished }
    fake.resumeFetches()
    try await waitUntil { task.isFinished }
    #expect(finished)
    #expect(task.result == .failure(.cancelled))
    #expect(fake.suspendedFetchCount == 0)
  }

  @Test("멈추기 전에 이미 취소됐으면 기록 뒤 멈추지 않고 바로 cancelled")
  func cancelledBeforeStart() async {
    let fake = DownloadClientFake()
    fake.suspendFetches()
    let result = await Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return await Self.fetchResult(fake)
    }.value

    #expect(result == .failure(.cancelled))
    #expect(fake.suspendedFetchCount == 0)
    #expect(fake.calls == [.fetchData(Self.url.url, maxBytes: 10)])
  }

  @Test("멈춘 fetch 를 여러 개 세고, resumeFetches 는 모두 재개한다")
  func countsAndResumesAll() async throws {
    let fake = DownloadClientFake()
    fake.suspendFetches()
    let first = FetchTask(fake: fake, url: Self.url)
    let second = FetchTask(fake: fake, url: Self.url)

    try await waitUntil { fake.suspendedFetchCount == 2 }
    first.cancel()
    try await waitUntil { fake.suspendedFetchCount == 1 }
    fake.resumeFetches()

    try await waitUntil { first.isFinished && second.isFinished }
    #expect(first.result == .failure(.cancelled))
    #expect(second.result == .success(Data()))
  }

  @Test("resumeFetches 뒤 새 호출은 멈추지 않는다")
  func resumeStopsSuspending() async {
    let fake = DownloadClientFake()
    fake.suspendFetches()
    fake.resumeFetches()

    #expect(await Self.fetchResult(fake) == .success(Data()))
    #expect(fake.suspendedFetchCount == 0)
  }

  @Test("멈춤은 받기(download)에 영향이 없고, 호출은 들어온 순서대로 기록된다")
  func independentOfDownloads() async throws {
    let fake = DownloadClientFake()
    fake.suspendFetches()
    let fetch = FetchTask(fake: fake, url: Self.url)
    try await waitUntil { fake.suspendedFetchCount == 1 }

    let file = try await fake.download(Self.url) { _ in }
    fake.resumeFetches()
    try await waitUntil { fetch.isFinished }

    #expect(file == .fake(index: 1))
    #expect(fake.calls == [.fetchData(Self.url.url, maxBytes: 10), .download(Self.url.url)])
  }

  @Test("주소별 결과가 있는 주소는 그 결과를, 없는 주소는 공통 결과를 돌려준다")
  func perURLResult() async {
    let fake = DownloadClientFake()
    fake.setFetchResult(.success(Data("common".utf8)))
    fake.setFetchResult(.failure(.httpStatus(404)), for: Self.otherURL)

    #expect(await Self.fetchResult(fake) == .success(Data("common".utf8)))
    #expect(await Self.fetchResult(fake, url: Self.otherURL) == .failure(.httpStatus(404)))
    #expect(fake.calls == [.fetchData(Self.url.url, maxBytes: 10), .fetchData(Self.otherURL.url, maxBytes: 10)])
  }

  @Test("주소별 멈춤은 그 주소만 기다리게 하고, 그 주소만 재개하거나 취소할 수 있다")
  func perURLSuspension() async throws {
    let fake = DownloadClientFake()
    fake.suspendFetches(for: Self.otherURL)
    let first = FetchTask(fake: fake, url: Self.otherURL)
    let second = FetchTask(fake: fake, url: Self.otherURL)
    try await waitUntil { fake.suspendedFetchCount == 2 }

    // 멈추지 않은 주소는 바로 끝난다.
    #expect(await Self.fetchResult(fake) == .success(Data()))
    first.cancel()
    try await waitUntil { first.isFinished && fake.suspendedFetchCount == 1 }
    #expect(first.result == .failure(.cancelled))
    #expect(!second.isFinished)

    fake.resumeFetches(for: Self.otherURL)
    try await waitUntil { second.isFinished }
    #expect(second.result == .success(Data()))
    #expect(fake.suspendedFetchCount == 0)
    // 재개한 주소의 다음 호출은 기다리지 않는다.
    #expect(await Self.fetchResult(fake, url: Self.otherURL) == .success(Data()))
  }

  @Test("공통 resumeFetches 는 주소별 멈춤도 풀고, 이후 그 주소도 기다리지 않는다")
  func resumeAllClearsPerURL() async throws {
    let fake = DownloadClientFake()
    fake.suspendFetches(for: Self.otherURL)
    let task = FetchTask(fake: fake, url: Self.otherURL)
    try await waitUntil { fake.suspendedFetchCount == 1 }

    fake.resumeFetches()
    try await waitUntil { task.isFinished }
    #expect(task.result == .success(Data()))
    #expect(await Self.fetchResult(fake, url: Self.otherURL) == .success(Data()))
    #expect(fake.suspendedFetchCount == 0)
  }

  @Test("공통 멈춤은 모든 주소를 멈추고, 주소별 재개는 공통 멈춤을 풀지 않는다")
  func commonSuspensionCoversAllURLs() async throws {
    let fake = DownloadClientFake()
    fake.suspendFetches()
    let first = FetchTask(fake: fake, url: Self.url)
    let second = FetchTask(fake: fake, url: Self.otherURL)
    try await waitUntil { fake.suspendedFetchCount == 2 }

    // 그 주소로 기다리던 호출만 깨우고, 공통 멈춤이 남아 그 주소의 다음 호출은 다시 기다린다.
    fake.resumeFetches(for: Self.otherURL)
    try await waitUntil { second.isFinished && fake.suspendedFetchCount == 1 }
    #expect(!first.isFinished)
    let third = FetchTask(fake: fake, url: Self.otherURL)
    try await waitUntil { fake.suspendedFetchCount == 2 }
    #expect(!third.isFinished)

    fake.resumeFetches()
    try await waitUntil { first.isFinished && third.isFinished }
    #expect(first.result == .success(Data()))
    #expect(third.result == .success(Data()))
  }

  static func fetchResult(
    _ fake: DownloadClientFake,
    url: DownloadURL = Self.url
  ) async -> Result<Data, DownloadError> {
    do throws(DownloadError) {
      return try await .success(fake.fetchData(url, maxBytes: 10))
    } catch {
      return .failure(error)
    }
  }
}

/// 끝났는지와 결과를 볼 수 있는 fetch 작업.
private final class FetchTask: Sendable {
  private let box: ResultBox
  private let task: Task<Void, Never>

  init(fake: DownloadClientFake, url: DownloadURL) {
    let box = ResultBox()
    self.box = box
    self.task = Task {
      do throws(DownloadError) {
        try await box.set(.success(fake.fetchData(url, maxBytes: 10)))
      } catch {
        box.set(.failure(error))
      }
    }
  }

  var isFinished: Bool {
    self.box.result != nil
  }

  var result: Result<Data, DownloadError>? {
    self.box.result
  }

  func cancel() {
    self.task.cancel()
  }
}

/// fetch 결과 기록.
private final class ResultBox: Sendable {
  private let stored = Mutex<Result<Data, DownloadError>?>(nil)

  var result: Result<Data, DownloadError>? {
    self.stored.withLock { $0 }
  }

  func set(_ result: Result<Data, DownloadError>) {
    self.stored.withLock { $0 = result }
  }
}

/// `waitUntil` 과 같지만 10초가 지나면 실패를 기록하고 false 를 돌려준다 (뒤의 정리를 하도록 던지지 않는다).
private func waitUntilOrTimeout(
  _ condition: () -> Bool,
  sourceLocation: SourceLocation = #_sourceLocation
) async -> Bool {
  let deadline = ContinuousClock.now + .seconds(10)
  while !condition() {
    guard ContinuousClock.now < deadline else {
      Issue.record("10초 안에 조건이 참이 되지 않았다", sourceLocation: sourceLocation)
      return false
    }
    try? await Task.sleep(for: .milliseconds(10))
  }
  return true
}
