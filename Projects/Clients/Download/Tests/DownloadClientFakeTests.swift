import Core
import DownloadInterface
import DownloadTesting
import Foundation
import Synchronization
import Testing

struct DownloadClientFakeTests {
  static let url = DownloadURL("https://example.com/build.zip")!

  @Test("기본은 샘플 진행 뒤 k 번째 호출에 fake(index: k), 호출을 기록한다")
  func defaults() async throws {
    let fake = DownloadClientFake()
    let log = Recorder<DownloadProgress>()

    let first = try await fake.download(Self.url) { log.append($0) }
    let second = try await fake.download(Self.url) { _ in }
    let data = try await fake.fetchData(Self.url, maxBytes: 4096)
    await fake.removeDownloaded(first)
    await fake.removeLeftoverDownloads()

    #expect(first == .fake(index: 1))
    #expect(second == .fake(index: 2))
    #expect(data.isEmpty)
    #expect(log.values == DownloadProgress.samples)
    #expect(fake.calls == [
      .download(Self.url.url),
      .download(Self.url.url),
      .fetchData(Self.url.url, maxBytes: 4096),
      .removeDownloaded(.fake(index: 1)),
    ])
    #expect(fake.leftoverCleanupCount == 1)
  }

  @Test("받기 이름을 주소와 함께 기록하고, 기본 결과의 파일은 그 이름을 따른다")
  func recordsFileName() async throws {
    let fake = DownloadClientFake()

    let plain = try await fake.download(Self.url) { _ in }
    let apk = try await fake.download(Self.url, savingAs: .apk) { _ in }

    #expect(plain == .fake(index: 1))
    #expect(plain.file.lastPathComponent == "download")
    #expect(apk == .fake(index: 2, name: .apk))
    #expect(apk.file.lastPathComponent == "download.apk")
    #expect(fake.downloadRequests == [
      DownloadClientFake.DownloadRequest(url: Self.url, name: .download),
      DownloadClientFake.DownloadRequest(url: Self.url, name: .apk),
    ])
    #expect(fake.calls == [.download(Self.url.url), .download(Self.url.url)])
  }

  @Test("설정한 진행을 순서대로 알리고 설정한 결과로 끝난다")
  func script() async throws {
    let fake = DownloadClientFake()
    let file = DownloadedFile.fake(index: 9)
    fake.setDownloadScript(progress: DownloadProgress.unknownTotalSamples, result: .success(file))
    fake.setFetchResult(.success(Data("{}".utf8)))
    let log = Recorder<DownloadProgress>()

    #expect(try await fake.download(Self.url) { log.append($0) } == file)
    #expect(log.values == DownloadProgress.unknownTotalSamples)
    #expect(try await fake.fetchData(Self.url, maxBytes: 10) == Data("{}".utf8))
  }

  @Test("주소별 결과가 있는 주소는 그 결과를, 없는 주소는 공통 결과(없으면 fake(index:))를 돌려준다")
  func perURLDownloadResult() async throws {
    let fake = DownloadClientFake()
    let other = try #require(DownloadURL("https://example.org/other.zip"))
    let file = DownloadedFile(
      file: URL(filePath: "/x/download"),
      folder: URL(filePath: "/x/"),
      byteCount: 3,
      mimeType: nil
    )
    fake.setDownloadResult(.success(file), for: other)
    fake.setDownloadResult(.failure(.httpStatus(404)), for: Self.url)

    func result(_ url: DownloadURL) async -> Result<DownloadedFile, DownloadError> {
      do throws(DownloadError) {
        return try await .success(fake.download(url) { _ in })
      } catch {
        return .failure(error)
      }
    }

    let first = await result(Self.url)
    let second = await result(other)
    let third = try await result(#require(DownloadURL("https://example.net/x.zip")))

    #expect(first == .failure(.httpStatus(404)))
    #expect(second == .success(file))
    #expect(third == .success(.fake(index: 3)))
  }

  @Test("설정한 에러를 던진다")
  func errors() async {
    let fake = DownloadClientFake()
    fake.setDownloadScript(progress: [], result: .failure(.httpStatus(404)))
    fake.setFetchResult(.failure(.tooLarge))

    await #expect(throws: DownloadError.httpStatus(404)) { try await fake.download(Self.url) { _ in } }
    await #expect(throws: DownloadError.tooLarge) { try await fake.fetchData(Self.url, maxBytes: 10) }
  }

  @Test("멈춘 받기는 기록된 뒤 기다리고, 보낸 진행을 받고, 재개되면 끝난다")
  func suspendAndResume() async throws {
    let fake = DownloadClientFake()
    fake.setDownloadScript(progress: [], result: nil)
    fake.suspendDownloads()
    let log = Recorder<DownloadProgress>()
    let task = Task { try await fake.download(Self.url) { log.append($0) } }

    try await waitFor { fake.suspendedDownloadCount == 1 }
    #expect(fake.calls == [.download(Self.url.url)])
    await fake.sendDownloadProgress(DownloadProgress(receivedBytes: 1, expectedBytes: 2))
    fake.resumeDownloads()

    #expect(try await task.value == .fake(index: 1))
    #expect(log.values == [DownloadProgress(receivedBytes: 1, expectedBytes: 2)])
  }

  @Test("멈춘 동안 Task 가 취소되면 cancelled")
  func cancelWhileSuspended() async throws {
    let fake = DownloadClientFake()
    fake.suspendDownloads()
    let task = Task { try await fake.download(Self.url) { _ in } }

    try await waitFor { fake.suspendedDownloadCount == 1 }
    task.cancel()

    await #expect(throws: DownloadError.cancelled) { try await task.value }
    #expect(fake.suspendedDownloadCount == 0)
  }

  @Test("시작 전에 취소됐으면 기록 뒤 진행 없이 cancelled")
  func cancelledBeforeStart() async {
    let fake = DownloadClientFake()
    let log = Recorder<DownloadProgress>()
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await fake.download(Self.url) { log.append($0) }
    }

    await #expect(throws: DownloadError.cancelled) { try await task.value }
    #expect(log.values.isEmpty)
    #expect(fake.calls == [.download(Self.url.url)])
  }

  @Test("진행 사이에 취소되면 남은 진행을 알리지 않고 cancelled")
  func cancelBetweenProgress() async {
    let fake = DownloadClientFake()
    let log = Recorder<DownloadProgress>()
    let task = Task {
      try await fake.download(Self.url) { value in
        log.append(value)
        withUnsafeCurrentTask { $0?.cancel() }
      }
    }

    await #expect(throws: DownloadError.cancelled) { try await task.value }
    #expect(log.values == [DownloadProgress.samples[0]])
  }

  @Test("마지막 진행 콜백 안에서 취소되면 결과 대신 cancelled (Impl 의 늦은 취소와 같은 계약)")
  func cancelInLastProgress() async {
    let fake = DownloadClientFake()
    let last = DownloadProgress.samples[DownloadProgress.samples.count - 1]
    let log = Recorder<DownloadProgress>()
    let task = Task {
      try await fake.download(Self.url) { value in
        log.append(value)
        if value == last {
          withUnsafeCurrentTask { $0?.cancel() }
        }
      }
    }

    await #expect(throws: DownloadError.cancelled) { try await task.value }
    #expect(log.values == DownloadProgress.samples)
  }

  @Test("fetchData 도 취소된 Task 면 cancelled")
  func cancelledFetch() async {
    let fake = DownloadClientFake()
    fake.setFetchResult(.success(Data("{}".utf8)))
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await fake.fetchData(Self.url, maxBytes: 10)
    }

    await #expect(throws: DownloadError.cancelled) { try await task.value }
  }

  @Test("fake(index:) 는 고정 경로·크기·형식")
  func samples() {
    let file = DownloadedFile.fake(index: 3)
    #expect(file.folder.path(percentEncoded: false) == "/tmp/SimLauncher-Download-Fake-3/")
    #expect(file.file.path(percentEncoded: false) == "/tmp/SimLauncher-Download-Fake-3/download")
    #expect(file.byteCount == 1024)
    #expect(file.mimeType == "application/zip")
  }
}

/// 멈춘 받기에 진행을 넘기는 중 온 취소·재개. 넘기는 중인 콜백은 문(`Gate`)에서 멈추고, 어느 받기가 먼저 넘겨받았는지는
/// 신호로 고른다 (멈춘 받기 목록의 순서는 정해지지 않는다).
struct DownloadClientFakeDeliveryTests {
  static let url = DownloadURL("https://example.com/build.zip")!
  static let progress = DownloadProgress(receivedBytes: 1, expectedBytes: 2)

  @Test("다른 받기에 진행을 넘기는 중 취소된 받기는 돌아온 뒤 진행을 받지 않는다")
  func otherCancelledDuringDelivery() async throws {
    let fake = DownloadClientFake()
    fake.setDownloadScript(progress: [], result: nil)
    fake.suspendDownloads()
    let gate = Gate()
    let log = Recorder<String>()
    let (signals, signal) = AsyncStream<String>.makeStream()
    var tasks: [String: Task<DownloadedFile, any Error>] = [:]
    for name in ["A", "B"] {
      tasks[name] = Task {
        try await fake.download(Self.url) { _ in
          log.append(name)
          signal.yield(name)
          await gate.wait()
        }
      }
    }
    try await waitFor { fake.suspendedDownloadCount == 2 }
    let sender = Task { await fake.sendDownloadProgress(Self.progress) }
    var iterator = signals.makeAsyncIterator()
    let first = try #require(await iterator.next())
    let other = try #require(tasks[first == "A" ? "B" : "A"])

    other.cancel()
    await #expect(throws: DownloadError.cancelled) { try await other.value }
    gate.open()
    await sender.value
    let delivering = try #require(tasks[first])
    delivering.cancel()

    await #expect(throws: DownloadError.cancelled) { try await delivering.value }
    #expect(log.values == [first])
  }

  @Test("다른 받기에 진행을 넘기는 중 재개된 받기는 돌아온 뒤 진행을 받지 않는다")
  func otherResumedDuringDelivery() async throws {
    let fake = DownloadClientFake()
    fake.setDownloadScript(progress: [], result: nil)
    fake.suspendDownloads()
    let gate = Gate()
    let log = Recorder<String>()
    let (signals, signal) = AsyncStream<String>.makeStream()
    var tasks: [String: Task<DownloadedFile, any Error>] = [:]
    for name in ["A", "B"] {
      tasks[name] = Task {
        try await fake.download(Self.url) { _ in
          log.append(name)
          signal.yield(name)
          await gate.wait()
        }
      }
    }
    try await waitFor { fake.suspendedDownloadCount == 2 }
    let sender = Task { await fake.sendDownloadProgress(Self.progress) }
    var iterator = signals.makeAsyncIterator()
    let first = try #require(await iterator.next())
    let other = try #require(tasks[first == "A" ? "B" : "A"])
    let delivering = try #require(tasks[first])
    let fakes: [DownloadedFile] = [.fake(index: 1), .fake(index: 2)]

    fake.resumeDownloads()
    #expect(try await fakes.contains(other.value))
    gate.open()
    await sender.value

    #expect(try await fakes.contains(delivering.value))
    #expect(log.values == [first])
  }

  @Test("진행 콜백 중 그 받기가 취소되면 콜백이 끝난 뒤에 cancelled 로 돌아온다")
  func selfCancelledDuringDelivery() async throws {
    let fake = DownloadClientFake()
    fake.setDownloadScript(progress: [], result: nil)
    fake.suspendDownloads()
    let gate = Gate()
    let log = Recorder<String>()
    let (signals, signal) = AsyncStream<String>.makeStream()
    let task = Task {
      defer { log.append("returned") }
      return try await fake.download(Self.url) { _ in
        log.append("start")
        signal.yield("start")
        await gate.wait()
        log.append("end")
      }
    }
    try await waitFor { fake.suspendedDownloadCount == 1 }
    let sender = Task { await fake.sendDownloadProgress(Self.progress) }
    var iterator = signals.makeAsyncIterator()
    _ = await iterator.next()

    task.cancel()
    // 옛 구조처럼 콜백이 끝나기 전에 돌아가 버리면 그 기회를 준다 (회귀 검출용).
    for _ in 0 ..< 1000 {
      await Task.yield()
    }
    log.append("gate open")
    gate.open()

    await #expect(throws: DownloadError.cancelled) { try await task.value }
    await sender.value
    #expect(log.values == ["start", "gate open", "end", "returned"])
  }

  @Test("진행 콜백 안에서 resumeDownloads 를 불러도 멈추지 않고, 깨운 뒤의 진행은 넘기지 않는다")
  func resumeInsideCallback() async throws {
    let fake = DownloadClientFake()
    fake.setDownloadScript(progress: [], result: nil)
    fake.suspendDownloads()
    let log = Recorder<DownloadProgress>()
    let task = Task {
      try await fake.download(Self.url) { value in
        log.append(value)
        fake.resumeDownloads()
      }
    }
    try await waitFor { fake.suspendedDownloadCount == 1 }
    let first = DownloadProgress(receivedBytes: 1, expectedBytes: 2)
    let second = DownloadProgress(receivedBytes: 2, expectedBytes: 2)

    await fake.sendDownloadProgress(first)
    await fake.sendDownloadProgress(second)

    #expect(try await task.value == .fake(index: 1))
    #expect(log.values == [first])
  }
}

/// 받은 값 기록.
private final class Recorder<Value: Sendable>: Sendable {
  private let recorded = Mutex<[Value]>([])

  var values: [Value] {
    self.recorded.withLock { $0 }
  }

  func append(_ value: Value) {
    self.recorded.withLock { $0.append(value) }
  }
}

/// 열릴 때까지 기다리게 하는 문. 한 번 열면 계속 열려 있다.
private final class Gate: Sendable {
  private let state = Mutex<(isOpen: Bool, waiters: [CheckedContinuation<Void, Never>])>((false, []))

  func wait() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      // 열림 확인과 continuation 저장을 한 lock 안에서 해야 open 이 먼저 와도 놓치지 않는다.
      let isOpen = self.state.withLock { state in
        guard !state.isOpen else { return true }
        state.waiters.append(continuation)
        return false
      }
      if isOpen {
        continuation.resume()
      }
    }
  }

  func open() {
    let waiters = self.state.withLock { state in
      state.isOpen = true
      let waiters = state.waiters
      state.waiters = []
      return waiters
    }
    for waiter in waiters {
      waiter.resume()
    }
  }
}

/// 조건이 참이 될 때까지 10ms 마다 본다. 10초가 지나면 실패.
private func waitFor(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
  let deadline = ContinuousClock.now + .seconds(10)
  while !condition() {
    guard ContinuousClock.now < deadline else {
      Issue.record("10초 안에 조건이 참이 되지 않았다", sourceLocation: sourceLocation)
      throw CancellationError()
    }
    try await Task.sleep(for: .milliseconds(10))
  }
}
