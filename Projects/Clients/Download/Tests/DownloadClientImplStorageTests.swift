import Core
import DownloadInterface
import Foundation
import Testing
@testable import DownloadImpl

/// `download` 의 디스크 여유·임시 폴더·파일 쓰기 실패.
struct DownloadClientImplStorageTests {
  @Test("Content-Length 가 여유보다 크면 본문을 받기 전에 멈추고 insufficientDiskSpace, 폴더 없음")
  func insufficientDiskSpace() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    // 끝내지 않는 시나리오: Impl 이 멈추지 않으면 끝나지 않는다. 조각 없이 멈춘 스텁은 응답이 delegate 에 오지 않아(확인함) 하나 보낸다.
    let url = StubURLProtocol.registerDownload(
      .respond(status: 200, headers: ["Content-Length": "5000"], chunks: [Data(count: 1000)], finish: false)
    )

    await #expect(throws: DownloadError.insufficientDiskSpace) {
      try await tmp.client(availableCapacity: { _ in 1000 }).download(url) { _ in }
    }
    try await waitUntil { StubURLProtocol.stopCount(url.url) >= 1 }
    #expect(tmp.names.isEmpty)
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("여유를 읽지 못하면(nil) 비교를 건너뛰고 성공한다")
  func unknownCapacitySkipsCheck() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let url = StubURLProtocol.registerDownload(
      .respond(status: 200, headers: ["Content-Length": "3000"], chunks: DownloadClientImplTests.chunks, finish: true)
    )

    let downloaded = try await tmp.client(availableCapacity: { _ in nil }).download(url) { _ in }

    #expect(downloaded.byteCount == 3000)
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  static let writeFailureCases: [(NSError, DownloadError)] = [
    (
      NSError(
        domain: NSCocoaErrorDomain,
        code: 640,
        userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 28)]
      ),
      .insufficientDiskSpace
    ),
    (NSError(domain: NSPOSIXErrorDomain, code: 13), .storageUnavailable),
  ]

  @Test(
    "쓰기 실패: 디스크가 찬 모양(Cocoa 640 ← POSIX 28)이면 insufficientDiskSpace, 그 밖은 storageUnavailable, 폴더 없음",
    arguments: Self.writeFailureCases
  )
  func writeFailure(error: NSError, expected: DownloadError) async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let url = StubURLProtocol.registerDownload(
      .respond(status: 200, headers: ["Content-Length": "3000"], chunks: DownloadClientImplTests.chunks, finish: true)
    )

    await #expect(throws: expected) {
      try await tmp.client(openSink: { _ in FailingSink(error: error) }).download(url) { _ in }
    }
    #expect(tmp.names.isEmpty)
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test(
    "파일 만들기 실패: ENOSPC 면 insufficientDiskSpace, EACCES 면 storageUnavailable, 폴더 없음",
    arguments: [(POSIXErrorCode.ENOSPC, DownloadError.insufficientDiskSpace), (.EACCES, .storageUnavailable)]
  )
  func openSinkFailure(code: POSIXErrorCode, expected: DownloadError) async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let url = StubURLProtocol.registerDownload(
      .respond(status: 200, headers: ["Content-Length": "3000"], chunks: DownloadClientImplTests.chunks, finish: true)
    )

    await #expect(throws: expected) {
      try await tmp.client(openSink: { _ in throw POSIXError(code) }).download(url) { _ in }
    }
    #expect(tmp.names.isEmpty)
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("임시 폴더가 없거나 파일이면 storageUnavailable 이고 요청하지 않는다")
  func storageUnavailable() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let missing = tmp.url.appending(path: "missing", directoryHint: .isDirectory)
    let file = tmp.url.appending(path: "file", directoryHint: .notDirectory)
    try Data("x".utf8).write(to: file)
    let url = StubURLProtocol.registerDownload(
      .respond(status: 200, headers: ["Content-Length": "3000"], chunks: DownloadClientImplTests.chunks, finish: true)
    )

    for directory in [missing, file] {
      let client = DownloadClientImpl(temporaryDirectory: directory, protocolClasses: [StubURLProtocol.self])
      await #expect(throws: DownloadError.storageUnavailable) {
        try await client.download(url) { _ in }
      }
    }
    #expect(StubURLProtocol.startCount(url.url) == 0)
    #expect(tmp.names == ["file"])
    StubURLProtocol.expectNoUnregisteredRequests()
  }
}
