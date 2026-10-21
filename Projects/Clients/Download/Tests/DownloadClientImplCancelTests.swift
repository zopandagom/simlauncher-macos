import Core
import DownloadInterface
import Foundation
import Testing
@testable import DownloadImpl

/// `download` 의 취소. 진행 콜백은 호출한 Task 안에서 불리므로, 콜백 안에서 그 Task 를 취소해 시점을 정확히 맞춘다.
struct DownloadClientImplCancelTests {
  @Test("받는 중 취소: 전송을 멈추고 폴더를 지운 뒤 cancelled, 돌아온 뒤 진행 콜백 없음")
  func cancelWhileReceiving() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    // 응답과 첫 조각만 보내고 끝내지 않는다: 취소해야만 끝난다.
    let url = StubURLProtocol.registerDownload(
      .respond(status: 200, headers: ["Content-Length": "3000"], chunks: [Data(count: 1000)], finish: false)
    )
    let log = ProgressLog()
    let client = tmp.client()

    let task = Task {
      try await client.download(url) { value in
        log.append(value)
        withUnsafeCurrentTask { $0?.cancel() }
      }
    }

    await #expect(throws: DownloadError.cancelled) { try await task.value }
    let countAtReturn = log.values.count
    try await Task.sleep(for: .milliseconds(50))
    #expect(log.values == [progress(0, 3000)])
    #expect(log.values.count == countAtReturn)
    try await waitUntil { StubURLProtocol.stopCount(url.url) >= 1 }
    #expect(tmp.names.isEmpty)
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("밖에서 Task 를 취소해도 cancelled, 폴더 없음")
  func cancelFromOutside() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let url = StubURLProtocol.registerDownload(
      .respond(status: 200, headers: ["Content-Length": "3000"], chunks: [Data(count: 1000)], finish: false)
    )
    let client = tmp.client()
    let task = Task { try await client.download(url) { _ in } }

    try await waitUntil { StubURLProtocol.startCount(url.url) == 1 }
    task.cancel()

    await #expect(throws: DownloadError.cancelled) { try await task.value }
    #expect(tmp.names.isEmpty)
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("시작 전에 이미 취소됐으면 폴더를 만들지 않고 요청도 보내지 않는다")
  func cancelledBeforeStart() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let url = StubURLProtocol.registerDownload(
      .respond(status: 200, headers: ["Content-Length": "3"], chunks: [Data("abc".utf8)], finish: true)
    )
    let client = tmp.client()

    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await client.download(url) { _ in }
    }

    await #expect(throws: DownloadError.cancelled) { try await task.value }
    #expect(StubURLProtocol.startCount(url.url) == 0)
    #expect(tmp.names.isEmpty)
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("전송이 성공한 뒤 마지막 진행 값을 처리하는 중 취소해도 받은 파일을 지우고 cancelled")
  func cancelAfterTransferSucceeded() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    // 멈춘 시계: 마지막 값 (3000, 3000) 은 완료 뒤에만 온다.
    let url = StubURLProtocol.registerDownload(
      .respond(
        status: 200,
        headers: ["Content-Length": "3000"],
        chunks: [Data(count: 1000), Data(count: 1000), Data(count: 1000)],
        finish: true
      )
    )
    let log = ProgressLog()
    let client = tmp.client()

    let task = Task {
      try await client.download(url) { value in
        log.append(value)
        if value.receivedBytes == 3000 {
          withUnsafeCurrentTask { $0?.cancel() }
        }
      }
    }

    await #expect(throws: DownloadError.cancelled) { try await task.value }
    #expect(log.values == [progress(0, 3000), progress(3000, 3000)])
    #expect(tmp.names.isEmpty)
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("동시에 여러 개를 받아도 서로 다른 폴더에 받는다")
  func concurrentDownloads() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let client = tmp.client()
    let first = StubURLProtocol.registerDownload(
      .respond(status: 200, headers: ["Content-Length": "1"], chunks: [Data("a".utf8)], finish: true)
    )
    let second = StubURLProtocol.registerDownload(
      .respond(status: 200, headers: ["Content-Length": "1"], chunks: [Data("b".utf8)], finish: true)
    )

    async let one = client.download(first) { _ in }
    async let two = client.download(second) { _ in }
    let results = try await [one, two]

    #expect(results[0].folder != results[1].folder)
    #expect(try Data(contentsOf: results[0].file) == Data("a".utf8))
    #expect(try Data(contentsOf: results[1].file) == Data("b".utf8))
    #expect(tmp.names.count == 2)
    StubURLProtocol.expectNoUnregisteredRequests()
  }
}
