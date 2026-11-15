import Core
import DownloadInterface
import DownloadTesting
import Foundation
import Testing
import UpdateCheckInterface
@testable import UpdateCheckImpl

struct UpdateCheckClientImplTests {
  static func repository() throws -> ReleaseRepository {
    try #require(ReleaseRepository("zopandagom/simlauncher-macos"))
  }

  @Test("요청 주소는 기본 저장소의 버전 파일 고정 주소, 상한은 64 KiB, 요청은 한 번")
  func requestsVersionFile() async throws {
    let download = DownloadClientFake()
    download.setFetchResult(.success(versionFileJSON("1.3.0")))
    let client = try UpdateCheckClientImpl(repository: Self.repository(), download: download)

    let latest = try await client.latestReleaseVersion()

    #expect(try latest == version("1.3.0"))
    let expectedURL = try #require(
      URL(
        string: "https://github.com/zopandagom/simlauncher-macos/releases/latest/download/SimLauncher-version.json"
      )
    )
    #expect(download.calls == [.fetchData(expectedURL, maxBytes: 65536)])
    #expect(UpdateCheckClientImpl.maxResponseBytes == 65536)
  }

  @Test("releasePageURL 은 저장소의 다운로드 페이지")
  func releasePageURL() throws {
    let client = try UpdateCheckClientImpl(repository: Self.repository(), download: DownloadClientFake())
    #expect(
      client.releasePageURL?.absoluteString == "https://github.com/zopandagom/simlauncher-macos/releases/latest"
    )
  }

  @Test("저장소가 없으면 요청 없이 notConfigured, releasePageURL 은 nil")
  func notConfigured() async {
    let download = DownloadClientFake()
    let client = UpdateCheckClientImpl(repository: nil, download: download)

    await #expect(throws: UpdateCheckError.notConfigured) { try await client.latestReleaseVersion() }
    #expect(download.calls.isEmpty)
    #expect(client.releasePageURL == nil)
  }

  @Test("숫자 버전이 아닌 버전 값은 nil")
  func unrecognizedVersion() async throws {
    let download = DownloadClientFake()
    download.setFetchResult(.success(versionFileJSON("sample-catalog")))
    let client = try UpdateCheckClientImpl(repository: Self.repository(), download: download)

    #expect(try await client.latestReleaseVersion() == nil)
  }

  @Test(
    "받기 실패는 매핑해 던진다",
    arguments: [
      (DownloadError.offline, UpdateCheckError.offline),
      (.httpStatus(403), .refused),
      (.httpStatus(429), .refused),
      (.httpStatus(404), .notFound),
      (.tooLarge, .unexpectedResponse),
      (.cancelled, .cancelled),
    ]
  )
  func mapsFailure(_ failure: DownloadError, _ expected: UpdateCheckError) async throws {
    let download = DownloadClientFake()
    download.setFetchResult(.failure(failure))
    let client = try UpdateCheckClientImpl(repository: Self.repository(), download: download)

    await #expect(throws: expected) { try await client.latestReleaseVersion() }
  }

  @Test("응답 해석 실패는 unexpectedResponse")
  func malformedResponse() async throws {
    let download = DownloadClientFake()
    download.setFetchResult(.success(Data("Not Found".utf8)))
    let client = try UpdateCheckClientImpl(repository: Self.repository(), download: download)

    await #expect(throws: UpdateCheckError.unexpectedResponse) { try await client.latestReleaseVersion() }
  }
}
