import Foundation
import Testing
@testable import Core

/// docs/CATALOG.md 가 링크하는 예시 파일(`Fixtures/catalog-example.json`)이 문서대로 해석되는지.
struct BuildCatalogExampleTests {
  @Test("규격 문서가 가리키는 예시 카탈로그는 문서대로 해석된다: 앱 2개 파일 순서, 버전은 최신순, 생략한 선택 필드는 nil, 빈 버전 목록")
  func example() throws {
    let catalog = try BuildCatalog(jsonData: Fixture.data("catalog-example"))

    #expect(catalog.apps.map(\.id.rawValue) == ["sample-app", "another-app"])
    #expect(catalog.apps.map(\.name) == ["Sample App", "Another App"])
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
}
