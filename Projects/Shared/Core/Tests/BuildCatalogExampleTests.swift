import Foundation
import Testing
@testable import Core

/// docs/CATALOG.md 가 링크하는 예시 파일(`Fixtures/catalog-example.json` 은 schemaVersion 2,
/// `Fixtures/catalog-example-v1.json` 은 schemaVersion 1)이 문서대로 해석되는지.
struct BuildCatalogExampleTests {
  @Test("v2 예시: 앱 3개 파일 순서, iOS·Android 가 같은 id 를 쓰고, 플랫폼별로 거르면 iOS 둘·Android 하나")
  func example() throws {
    let catalog = try BuildCatalog(jsonData: Fixture.data("catalog-example"))

    #expect(catalog.schemaVersion == 2)
    #expect(catalog.apps.map(\.id.rawValue) == ["com.example.sample", "com.example.sample", "another-app"])
    #expect(catalog.apps.map(\.platform) == [.ios, .android, .ios])
    #expect(catalog.apps(for: .ios).map(\.id.rawValue) == ["com.example.sample", "another-app"])
    #expect(catalog.apps(for: .android).map(\.id.rawValue) == ["com.example.sample"])

    let sampleID = BuildCatalog.AppID("com.example.sample")
    let iosSample = try #require(catalog.app(sampleID, for: .ios))
    #expect(iosSample.versions.map(\.id.rawValue) == ["build-42", "build-41"])
    let androidSample = try #require(catalog.app(sampleID, for: .android))
    #expect(androidSample.platform == .android)
    let apk = try #require(androidSample.versions.first)
    #expect(
      apk.buildURL.url.absoluteString
        == "https://github.com/example/sample-app/releases/download/build-42/SampleApp.apk"
    )
    #expect(catalog.app(BuildCatalog.AppID("another-app"), for: .android) == nil)
    #expect(catalog.apps.last?.versions.isEmpty == true)
  }

  @Test("v1 예시: 앱 2개 파일 순서, 모두 iOS, 버전은 최신순, 생략한 선택 필드는 nil, 빈 버전 목록")
  func exampleV1() throws {
    let catalog = try BuildCatalog(jsonData: Fixture.data("catalog-example-v1"))

    #expect(catalog.schemaVersion == 1)
    #expect(catalog.apps.map(\.id.rawValue) == ["sample-app", "another-app"])
    #expect(catalog.apps.map(\.name) == ["Sample App", "Another App"])
    #expect(catalog.apps.map(\.platform) == [.ios, .ios])
    #expect(catalog.apps(for: .android).isEmpty)
    let sample = try #require(catalog.apps.first)
    #expect(sample.versions.map(\.id.rawValue) == ["build-42", "build-41"])

    let newest = try #require(sample.versions.first)
    #expect(newest.name == "1.3.0 beta (42)")
    #expect(newest.branch == "feature/login")
    #expect(newest.tag == nil)
    #expect(newest.buildNumber == "42")
    #expect(milliseconds(newest.createdAt) == 1_792_555_729_073)
    #expect(
      newest.buildURL.url.absoluteString
        == "https://github.com/example/sample-app/releases/download/build-42/SampleApp.zip"
    )

    let older = try #require(sample.versions.last)
    #expect(older.name == "1.2.0 (41)")
    #expect(older.branch == "main")
    #expect(older.tag == "v1.2.0")
    #expect(older.buildNumber == "41")
    #expect(milliseconds(older.createdAt) == 1_792_487_700_000)
    #expect(
      older.buildURL.url.absoluteString
        == "https://github.com/example/sample-app/releases/download/build-41/SampleApp.zip"
    )

    #expect(catalog.apps.last?.versions.isEmpty == true)
  }

  @Test("카탈로그 크기 상한은 5 MiB 다")
  func maxByteCount() {
    #expect(BuildCatalog.maxByteCount == 5_242_880)
  }

  @Test("읽는 규격은 1~2, 가장 새 규격은 2")
  func schemaVersions() {
    #expect(BuildCatalog.supportedSchemaVersions == 1 ... 2)
    #expect(BuildCatalog.latestSchemaVersion == 2)
  }
}
