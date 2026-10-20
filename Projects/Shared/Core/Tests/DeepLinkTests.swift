import Foundation
import Testing
@testable import Core

struct DeepLinkTests {
  struct Accepted: Sendable, CustomTestStringConvertible {
    let raw: String
    let absoluteString: String

    var testDescription: String {
      self.raw.debugDescription
    }
  }

  @Test(
    "통과하는 입력은 앞뒤 공백을 빼고, 경로·쿼리는 퍼센트 인코딩하고, 호스트 한글은 퓨니코드로 바꾼다",
    arguments: [
      Accepted(raw: "  https://example.com \n", absoluteString: "https://example.com"),
      Accepted(raw: "https://example.com/a b", absoluteString: "https://example.com/a%20b"),
      Accepted(
        raw: "https://example.com/검색?q=한글",
        absoluteString: "https://example.com/%EA%B2%80%EC%83%89?q=%ED%95%9C%EA%B8%80"
      ),
      Accepted(
        raw: "https://example.com/%EA%B2%80%EC%83%89?q=%ED%95%9C%EA%B8%80",
        absoluteString: "https://example.com/%EA%B2%80%EC%83%89?q=%ED%95%9C%EA%B8%80"
      ),
      Accepted(raw: "https://example.com/a%20b", absoluteString: "https://example.com/a%20b"),
      Accepted(raw: "myapp://경로", absoluteString: "myapp://xn--289ak4t"),
      Accepted(raw: "MyApp://X", absoluteString: "MyApp://X"),
      Accepted(raw: "localhost:8080", absoluteString: "localhost:8080"),
      Accepted(raw: "mailto:a@example.com", absoluteString: "mailto:a@example.com"),
    ]
  )
  func accepted(testCase: Accepted) {
    #expect(DeepLink.problem(in: testCase.raw) == nil)
    #expect(DeepLink(testCase.raw)?.url.absoluteString == testCase.absoluteString)
  }

  @Test("앞뒤 공백·개행을 빼면 비는 입력은 empty", arguments: ["", "  \n"])
  func empty(raw: String) {
    #expect(DeepLink.problem(in: raw) == .empty)
    #expect(DeepLink(raw) == nil)
  }

  @Test(
    "URL(string:) 이 읽지 못하는 입력은 malformed",
    arguments: ["myapp://a b", "a b://x", "1abc://x", "192.168.0.1:8080"]
  )
  func malformed(raw: String) {
    #expect(DeepLink.problem(in: raw) == .malformed)
    #expect(DeepLink(raw) == nil)
  }

  @Test("스킴이 없거나 빈 입력은 missingScheme", arguments: ["hello", "example.com", "-h", "://x"])
  func missingScheme(raw: String) {
    #expect(DeepLink.problem(in: raw) == .missingScheme)
    #expect(DeepLink(raw) == nil)
  }
}
