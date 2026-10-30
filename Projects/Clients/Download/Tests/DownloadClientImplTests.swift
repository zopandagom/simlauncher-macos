import Core
import DownloadInterface
import Foundation
import Testing
@testable import DownloadImpl

/// `download` 의 성공·실패. 실제 네트워크 없이 `StubURLProtocol` 로 응답을 흉내 낸다.
struct DownloadClientImplTests {
  static let body = Data((0 ..< 3000).map { UInt8($0 % 251) })

  /// 3000 바이트를 1000 바이트 조각 셋으로 보낸다.
  static var chunks: [Data] {
    [body[0 ..< 1000], body[1000 ..< 2000], body[2000 ..< 3000]].map { Data($0) }
  }

  @Test("성공: 고정 이름 파일에 받고, 폴더·파일 권한과 진행 (0, 전체)·(전체, 전체) 를 확인한다")
  func success() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let url = StubURLProtocol.registerDownload(
      .respond(
        status: 200,
        headers: ["Content-Length": "3000", "Content-Type": "application/zip"],
        chunks: Self.chunks,
        finish: true
      )
    )
    let log = ProgressLog()

    let downloaded = try await tmp.client().download(url) { log.append($0) }

    #expect(try Data(contentsOf: downloaded.file) == Self.body)
    #expect(downloaded.byteCount == 3000)
    #expect(downloaded.mimeType == "application/zip")
    #expect(downloaded.file.lastPathComponent == "download")
    #expect(downloaded.file.deletingLastPathComponent().path(percentEncoded: false) == downloaded.folder
      .path(percentEncoded: false))
    #expect(downloaded.folder.deletingLastPathComponent().path(percentEncoded: false) == tmp.url
      .path(percentEncoded: false))
    let name = downloaded.folder.lastPathComponent
    #expect(name.hasPrefix("SimLauncher-Download-"))
    #expect(UUID(uuidString: String(name.dropFirst("SimLauncher-Download-".count))) != nil)
    #expect(mode(downloaded.folder) == 0o700)
    #expect(mode(downloaded.file) == 0o600)
    #expect(log.values == [progress(0, 3000), progress(3000, 3000)])
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("이름 .apk 면 <folder>/download.apk 에 받고 권한 0o600")
  func successAsAPK() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let url = StubURLProtocol.registerDownload(
      .respond(status: 200, headers: ["Content-Length": "3000"], chunks: Self.chunks, finish: true)
    )

    let downloaded = try await tmp.client().download(url, savingAs: .apk) { _ in }

    #expect(try Data(contentsOf: downloaded.file) == Self.body)
    #expect(downloaded.file.lastPathComponent == "download.apk")
    #expect(downloaded.file.deletingLastPathComponent().path(percentEncoded: false) == downloaded.folder
      .path(percentEncoded: false))
    #expect(mode(downloaded.file) == 0o600)
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("Content-Length 가 없으면 진행의 전체가 nil 이고 성공한다")
  func successWithoutContentLength() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let url = StubURLProtocol.registerDownload(.respond(status: 200, headers: [:], chunks: Self.chunks, finish: true))
    let log = ProgressLog()

    let downloaded = try await tmp.client().download(url) { log.append($0) }

    #expect(downloaded.byteCount == 3000)
    #expect(log.values == [progress(0, nil), progress(3000, nil)])
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("2xx 가 아닌 상태는 httpStatus 이고 폴더를 남기지 않는다", arguments: [404, 500, 401])
  func httpStatus(status: Int) async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let url = StubURLProtocol.registerDownload(
      .respond(status: status, headers: ["Content-Length": "3"], chunks: [Data("err".utf8)], finish: true)
    )

    await #expect(throws: DownloadError.httpStatus(status)) {
      try await tmp.client().download(url) { _ in }
    }
    #expect(tmp.names.isEmpty)
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("204 는 2xx 라 빈 파일로 성공한다: Content-Length: 0 이면 진행 [(0, 0)], 헤더가 없으면 [(0, nil)]")
  func noContent() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let client = tmp.client()
    let withLength = StubURLProtocol.registerDownload(
      .respond(status: 204, headers: ["Content-Length": "0"], chunks: [], finish: true)
    )
    let withoutLength = StubURLProtocol.registerDownload(.respond(status: 204, headers: [:], chunks: [], finish: true))
    let logWithLength = ProgressLog()
    let logWithoutLength = ProgressLog()

    let first = try await client.download(withLength) { logWithLength.append($0) }
    let second = try await client.download(withoutLength) { logWithoutLength.append($0) }

    #expect(first.byteCount == 0)
    #expect(try Data(contentsOf: first.file).isEmpty)
    #expect(logWithLength.values == [progress(0, 0)])
    #expect(second.byteCount == 0)
    #expect(logWithoutLength.values == [progress(0, nil)])
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("https 에서 http 로 리다이렉트하면 따라가지 않고 insecureRedirect, http 쪽 요청 0회, 폴더 없음")
  func redirectToHTTP() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let target = StubURLProtocol.register(
      .respond(status: 200, headers: ["Content-Length": "3"], chunks: [Data("abc".utf8)], finish: true),
      scheme: "http"
    )
    let url = StubURLProtocol.registerDownload(.redirect(location: target, status: 302))

    await #expect(throws: DownloadError.insecureRedirect) {
      try await tmp.client().download(url) { _ in }
    }
    #expect(StubURLProtocol.startCount(target) == 0)
    #expect(tmp.names.isEmpty)
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("https 에서 https 로 리다이렉트하면 따라가 성공하고 두 호스트 모두 요청을 받는다")
  func redirectToHTTPS() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let target = StubURLProtocol.register(
      .respond(status: 200, headers: ["Content-Length": "3000"], chunks: Self.chunks, finish: true)
    )
    let url = StubURLProtocol.registerDownload(.redirect(location: target, status: 302))

    let downloaded = try await tmp.client().download(url) { _ in }

    #expect(try Data(contentsOf: downloaded.file) == Self.body)
    #expect(StubURLProtocol.startCount(url.url) == 1)
    #expect(StubURLProtocol.startCount(target) == 1)
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  static let failureCases: [(URLError.Code, DownloadError)] = [
    (.notConnectedToInternet, .offline),
    (.dataNotAllowed, .offline),
    (.internationalRoamingOff, .offline),
    (.cannotFindHost, .hostNotFound),
    (.dnsLookupFailed, .hostNotFound),
    (.cannotConnectToHost, .cannotConnect),
    (.timedOut, .timedOut),
    (.networkConnectionLost, .connectionLost),
    (.serverCertificateUntrusted, .secureConnectionFailed),
    (.secureConnectionFailed, .secureConnectionFailed),
    (.appTransportSecurityRequiresSecureConnection, .insecureRedirect),
    (.httpTooManyRedirects, .failed),
    (.cancelled, .failed),
  ]

  @Test(
    "전송 실패 코드를 DownloadError 로 바꾸고 폴더를 남기지 않는다 (호출자가 취소하지 않은 -999 는 failed)",
    arguments: Self.failureCases
  )
  func transportFailure(code: URLError.Code, expected: DownloadError) async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let url = StubURLProtocol.registerDownload(.fail(code))

    await #expect(throws: expected) {
      try await tmp.client().download(url) { _ in }
    }
    #expect(tmp.names.isEmpty)
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("받은 크기가 Content-Length 보다 작게 끝나면 connectionLost, 폴더 없음")
  func shortBody() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let url = StubURLProtocol.registerDownload(
      .respond(status: 200, headers: ["Content-Length": "3000"], chunks: [Data(count: 1000)], finish: true)
    )

    await #expect(throws: DownloadError.connectionLost) {
      try await tmp.client().download(url) { _ in }
    }
    #expect(tmp.names.isEmpty)
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("진행 콜백이 느려도 성공하고, 받은 바이트는 늘기만 하며 연속한 같은 값이 없고 마지막은 (전체, 전체)")
  func slowProgressCallback() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let chunks = (0 ..< 5).map { _ in Data(count: 1000) }
    let url = StubURLProtocol.registerDownload(
      .respond(status: 200, headers: ["Content-Length": "5000"], chunks: chunks, finish: true)
    )
    let log = ProgressLog()

    let downloaded = try await tmp.client(now: Clocks.stepping()).download(url) { value in
      log.append(value)
      try? await Task.sleep(for: .milliseconds(20))
    }

    let values = log.values
    #expect(downloaded.byteCount == 5000)
    #expect(values.first == progress(0, 5000))
    #expect(values.last == progress(5000, 5000))
    for (previous, next) in zip(values, values.dropFirst()) {
      #expect(previous.receivedBytes < next.receivedBytes, "\(values)")
    }
    StubURLProtocol.expectNoUnregisteredRequests()
  }
}
