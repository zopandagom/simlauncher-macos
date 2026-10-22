import Foundation
import Testing
@testable import Core

struct BuildCatalogDecodingTests {
  @Test("예시 카탈로그를 init(jsonData:) 와 같은 값으로 해석한다")
  func example() async throws {
    let data = try Fixture.data("catalog-example")

    let decoded = try await BuildCatalog.decoded(from: data)

    #expect(try decoded == BuildCatalog(jsonData: data))
    #expect(!decoded.apps.isEmpty)
  }

  @Test("문제가 있으면 init(jsonData:) 와 같은 문제를 던진다")
  func problem() async {
    let html = Data("<html><body>로그인</body></html>".utf8)
    let unsupported = Data(#"{"schemaVersion":2,"apps":[]}"#.utf8)

    await #expect(throws: BuildCatalogProblem.notJSONObject) { try await BuildCatalog.decoded(from: html) }
    await #expect(throws: BuildCatalogProblem.unsupportedSchemaVersion(2)) {
      try await BuildCatalog.decoded(from: unsupported)
    }
  }
}
