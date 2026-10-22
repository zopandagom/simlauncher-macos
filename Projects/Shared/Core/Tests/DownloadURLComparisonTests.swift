import Foundation
import Testing
@testable import Core

struct DownloadURLComparisonTests {
  struct Pair: Sendable, CustomTestStringConvertible {
    let first: String
    let second: String

    init(_ first: String, _ second: String) {
      self.first = first
      self.second = second
    }

    var testDescription: String {
      "\(self.first) / \(self.second)"
    }
  }

  static func key(_ raw: String) throws -> String {
    try #require(DownloadURL(raw)).comparisonKey
  }

  @Test(
    "같은 자원을 가리키는 표기는 같은 키",
    arguments: [
      Pair("https://example.com/c.json", "HTTPS://EXAMPLE.COM/c.json"),
      Pair("https://example.com/c.json", "https://Example.Com/c.json"),
      Pair("https://example.com/c.json", "https://example.com:443/c.json"),
      Pair("https://example.com/c.json", "https://example.com:0443/c.json"),
      Pair("https://example.com", "https://example.com/"),
      Pair("https://example.com/%7Euser/c.json", "https://example.com/~user/c.json"),
      Pair("https://example.com/%7euser/c.json", "https://example.com/~user/c.json"),
      Pair("https://example.com/%41b.json", "https://example.com/Ab.json"),
      Pair("https://example.com/a%2fb.json", "https://example.com/a%2Fb.json"),
      Pair("https://example.com/c.json?x=%2f", "https://example.com/c.json?x=%2F"),
      Pair("https://example.com/c.json?x=%7e", "https://example.com/c.json?x=~"),
      Pair("https://example.com/./c.json", "https://example.com/c.json"),
      Pair("https://example.com/x/../c.json", "https://example.com/c.json"),
      Pair("https://example.com/a/./b/../c.json", "https://example.com/a/c.json"),
      Pair("https://example.com/c.json#top", "https://example.com/c.json"),
      Pair("https://example.com/c.json#", "https://example.com/c.json"),
      Pair("https://example.com/c.json?a=1#x", "https://example.com/c.json?a=1"),
      Pair("https://example.com/한글.json", "https://example.com/%ED%95%9C%EA%B8%80.json"),
      Pair("https://example.com/%ed%95%9c%ea%b8%80.json", "https://example.com/%ED%95%9C%EA%B8%80.json"),
      Pair("https://example.com/a b.json", "https://example.com/a%20b.json"),
      Pair("https://bücher.example/c.json", "https://xn--bcher-kva.example/c.json"),
      Pair("https://XN--BCHER-KVA.example/c.json", "https://xn--bcher-kva.example/c.json"),
      Pair("https://ex%41mple.com/c.json", "https://example.com/c.json"),
      Pair("  https://example.com/c.json\n", "https://example.com/c.json"),
    ]
  )
  func same(pair: Pair) throws {
    #expect(try Self.key(pair.first) == Self.key(pair.second))
  }

  @Test(
    "서버가 구분할 수 있는 차이는 다른 키",
    arguments: [
      Pair("https://example.com/catalog.json", "https://example.com/Catalog.json"),
      Pair("https://example.com/c/", "https://example.com/c"),
      Pair("https://example.com//c.json", "https://example.com/c.json"),
      Pair("https://example.com/c.json", "https://example.com:8443/c.json"),
      Pair("https://example.com/c.json?a=1", "https://example.com/c.json?a=2"),
      Pair("https://example.com/c.json?a=1&b=2", "https://example.com/c.json?b=2&a=1"),
      Pair("https://example.com/c.json", "https://example.com/c.json?"),
      Pair("https://example.com/a%2Fb.json", "https://example.com/a/b.json"),
      Pair("https://example.com/c.json", "https://other.example/c.json"),
      Pair("https://example.com./c.json", "https://example.com/c.json"),
    ]
  )
  func different(pair: Pair) throws {
    #expect(try Self.key(pair.first) != Self.key(pair.second))
  }

  @Test("정규화 예시의 키 문자열")
  func example() throws {
    #expect(
      try Self.key("HTTPS://Example.COM:443/a/./b/../%7euser/c%2fd.json?x=%2f#top")
        == "https://example.com/a/~user/c%2Fd.json?x=%2F"
    )
  }

  @Test("포트가 443 이 아니면 키에 남고, 빈 쿼리는 ? 로 남는다")
  func portAndEmptyQuery() throws {
    #expect(try Self.key("https://example.com:8443/c.json") == "https://example.com:8443/c.json")
    #expect(try Self.key("https://example.com/c.json?") == "https://example.com/c.json?")
    #expect(try Self.key("https://example.com") == "https://example.com/")
  }

  @Test("IPv6 호스트는 괄호로 감싼다")
  func ipv6() throws {
    #expect(try Self.key("https://[::1]/c.json") == "https://[::1]/c.json")
    #expect(try Self.key("https://[::1]:8443/c.json") == "https://[::1]:8443/c.json")
  }

  @Test("퍼센트 인코딩: 예약되지 않은 문자만 풀고, 나머지는 hex 를 대문자로, 끝이 잘린 % 는 그대로")
  func percentEncoding() {
    #expect(DownloadURL.normalizingPercentEncoding("%7e%2d%2E%5f%41%7a%30") == "~-._Az0")
    #expect(DownloadURL.normalizingPercentEncoding("%2f%3a%ed%95%9c") == "%2F%3A%ED%95%9C")
    #expect(DownloadURL.normalizingPercentEncoding("a%2") == "a%2")
    #expect(DownloadURL.normalizingPercentEncoding("a%zz") == "a%zz")
  }

  @Test(
    "점 세그먼트 제거 (RFC 3986 5.2.4)",
    arguments: [
      ("/a/b/c/./../../g", "/a/g"),
      ("/a/../../c", "/c"),
      ("/..", "/"),
      ("/.", "/"),
      ("/a/..", "/"),
      ("/a/.", "/a/"),
      ("/a/b/..", "/a/"),
      ("/./a", "/a"),
      ("/a/.b/..c", "/a/.b/..c"),
      ("//a", "//a"),
      ("/", "/"),
    ]
  )
  func dotSegments(input: String, expected: String) {
    #expect(DownloadURL.removingDotSegments(input) == expected)
  }
}
