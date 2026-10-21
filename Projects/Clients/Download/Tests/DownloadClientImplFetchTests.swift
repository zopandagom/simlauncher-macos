import Core
import DownloadInterface
import Foundation
import Testing
@testable import DownloadImpl

/// `fetchData`: 메모리로 받고 파일을 만들지 않는다.
struct DownloadClientImplFetchTests {
  @Test("성공하면 받은 내용을 돌려주고 임시 폴더에 아무것도 만들지 않는다")
  func success() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let body = Data(#"{"builds":[]}"#.utf8)
    let url = StubURLProtocol.registerDownload(
      .respond(status: 200, headers: ["Content-Length": "\(body.count)"], chunks: [body], finish: true)
    )

    let data = try await tmp.client().fetchData(url, maxBytes: 4096)

    #expect(data == body)
    #expect(tmp.names.isEmpty)
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("Content-Length 가 maxBytes 보다 크면 본문을 받기 전에 멈추고 tooLarge")
  func contentLengthOverLimit() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    // 끝내지 않는 시나리오: Impl 이 멈추지 않으면 끝나지 않는다. 조각 없이 멈춘 스텁은 응답이 delegate 에 오지 않아(확인함) 하나 보낸다.
    let url = StubURLProtocol.registerDownload(
      .respond(status: 200, headers: ["Content-Length": "5000"], chunks: [Data(count: 1000)], finish: false)
    )

    await #expect(throws: DownloadError.tooLarge) {
      try await tmp.client().fetchData(url, maxBytes: 4096)
    }
    try await waitUntil { StubURLProtocol.stopCount(url.url) >= 1 }
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("Content-Length 가 없으면 받는 중 maxBytes 를 넘는 순간 tooLarge, 정확히 maxBytes 면 성공")
  func bodyOverLimitWithoutContentLength() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let client = tmp.client()
    let chunks = (0 ..< 5).map { _ in Data(count: 1000) }
    // 끝내지 않는 시나리오: 넘는 순간 멈추지 않으면 끝나지 않는다.
    let over = StubURLProtocol.registerDownload(.respond(status: 200, headers: [:], chunks: chunks, finish: false))
    let exact = StubURLProtocol.registerDownload(.respond(status: 200, headers: [:], chunks: chunks, finish: true))

    await #expect(throws: DownloadError.tooLarge) {
      try await client.fetchData(over, maxBytes: 4096)
    }
    let data = try await client.fetchData(exact, maxBytes: 5000)

    try await waitUntil { StubURLProtocol.stopCount(over.url) >= 1 }
    #expect(data.count == 5000)
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("상태·리다이렉트·전송 실패는 download 와 같이 바꾼다")
  func failures() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let client = tmp.client()
    let notFound = StubURLProtocol.registerDownload(
      .respond(status: 404, headers: ["Content-Length": "3"], chunks: [Data("err".utf8)], finish: true)
    )
    let httpTarget = StubURLProtocol.register(
      .respond(status: 200, headers: ["Content-Length": "2"], chunks: [Data("{}".utf8)], finish: true),
      scheme: "http"
    )
    let toHTTP = StubURLProtocol.registerDownload(.redirect(location: httpTarget, status: 301))
    let timedOut = StubURLProtocol.registerDownload(.fail(.timedOut))

    await #expect(throws: DownloadError.httpStatus(404)) { try await client.fetchData(notFound, maxBytes: 4096) }
    await #expect(throws: DownloadError.insecureRedirect) { try await client.fetchData(toHTTP, maxBytes: 4096) }
    await #expect(throws: DownloadError.timedOut) { try await client.fetchData(timedOut, maxBytes: 4096) }
    #expect(StubURLProtocol.startCount(httpTarget) == 0)
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("받는 중 Task 를 취소하면 cancelled")
  func cancel() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let url = StubURLProtocol.registerDownload(
      .respond(status: 200, headers: ["Content-Length": "3000"], chunks: [Data(count: 1000)], finish: false)
    )
    let client = tmp.client()
    let task = Task { try await client.fetchData(url, maxBytes: 4096) }

    try await waitUntil { StubURLProtocol.startCount(url.url) == 1 }
    task.cancel()

    await #expect(throws: DownloadError.cancelled) { try await task.value }
    try await waitUntil { StubURLProtocol.stopCount(url.url) >= 1 }
    StubURLProtocol.expectNoUnregisteredRequests()
  }
}
