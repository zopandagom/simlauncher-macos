import Foundation
import Testing
@testable import Core

struct DownloadURLTests {
  struct Accepted: Sendable, CustomTestStringConvertible {
    let raw: String
    let absoluteString: String

    var testDescription: String {
      self.raw.debugDescription
    }
  }

  @Test(
    "통과하는 입력은 앞뒤 공백을 빼고, 경로는 퍼센트 인코딩하고, 호스트 한글은 퓨니코드로 바꾸고, 포트·쿼리·조각은 둔다",
    arguments: [
      Accepted(raw: "  https://example.com/app.zip \n", absoluteString: "https://example.com/app.zip"),
      Accepted(raw: "HTTPS://Example.COM/a.zip", absoluteString: "HTTPS://Example.COM/a.zip"),
      Accepted(
        raw: "https://example.com/빌드 1.zip",
        absoluteString: "https://example.com/%EB%B9%8C%EB%93%9C%201.zip"
      ),
      Accepted(raw: "https://예시.com/a.zip", absoluteString: "https://xn--vv4b11d.com/a.zip"),
      Accepted(
        raw: "https://example.com:8443/a.zip?token=1#part",
        absoluteString: "https://example.com:8443/a.zip?token=1#part"
      ),
      Accepted(raw: "https://example.com:99999/a", absoluteString: "https://example.com:99999/a"),
      Accepted(raw: "https://[::1]/a.zip", absoluteString: "https://[::1]/a.zip"),
      Accepted(raw: "https://127.0.0.1/a.zip", absoluteString: "https://127.0.0.1/a.zip"),
    ]
  )
  func accepted(testCase: Accepted) {
    #expect(DownloadURL.problem(in: testCase.raw) == nil)
    #expect(DownloadURL(testCase.raw)?.url.absoluteString == testCase.absoluteString)
  }

  @Test("앞뒤 공백·개행을 빼면 비는 입력은 empty", arguments: ["", "  \n"])
  func empty(raw: String) {
    #expect(DownloadURL.problem(in: raw) == .empty)
    #expect(DownloadURL(raw) == nil)
  }

  @Test(
    "URL(string:) 이 읽지 못하는 입력은 malformed",
    arguments: ["https://exa mple.com/a.zip", "https://example.com\nhttps://b.com"]
  )
  func malformed(raw: String) {
    #expect(DownloadURL.problem(in: raw) == .malformed)
    #expect(DownloadURL(raw) == nil)
  }

  @Test(
    "스킴이 https 가 아니거나 없으면 notHTTPS",
    arguments: [
      "http://example.com/a.zip",
      "ftp://example.com/a.zip",
      "file:///tmp/a.zip",
      "example.com/a.zip",
      "//example.com/a.zip",
    ]
  )
  func notHTTPS(raw: String) {
    #expect(DownloadURL.problem(in: raw) == .notHTTPS)
    #expect(DownloadURL(raw) == nil)
  }

  @Test("https 지만 호스트가 없으면 missingHost", arguments: ["https://", "https:///a.zip"])
  func missingHost(raw: String) {
    #expect(DownloadURL.problem(in: raw) == .missingHost)
    #expect(DownloadURL(raw) == nil)
  }

  @Test(
    "사용자 이름·비밀번호가 들어 있으면 hasCredentials (빈 사용자 이름 포함)",
    arguments: ["https://user:pw@example.com/a.zip", "https://user@example.com/a.zip", "https://@example.com/a"]
  )
  func hasCredentials(raw: String) {
    #expect(DownloadURL.problem(in: raw) == .hasCredentials)
    #expect(DownloadURL(raw) == nil)
  }

  @Test("문제가 여럿이면 앞 순서의 문제 하나만: http 이면서 자격 증명이 있으면 notHTTPS")
  func firstProblemWins() {
    #expect(DownloadURL.problem(in: "http://user:pw@example.com/a.zip") == .notHTTPS)
    #expect(DownloadURL.problem(in: "https://user@/a.zip") == .missingHost)
  }
}
