import Foundation
import Testing
@testable import Core

struct CatalogURLListTests {
  @Test("저장 순서대로 상태를 매긴다: 쓸 수 있음·주소 문제·앞 항목과 같은 카탈로그")
  func entries() throws {
    let raws = [
      "https://example.com/catalog.json",
      "http://example.com/catalog.json",
      "",
      "https://user:pw@example.com/catalog.json",
      "HTTPS://EXAMPLE.COM:443/catalog.json#top",
      "https://other.example/catalog.json",
      "https://example.com/./catalog.json",
    ]
    let first = try #require(DownloadURL(raws[0]))
    let other = try #require(DownloadURL(raws[5]))

    #expect(CatalogURLList.entries(raws) == [
      CatalogURLEntry(raw: raws[0], status: .usable(first)),
      CatalogURLEntry(raw: raws[1], status: .invalid(.notHTTPS)),
      CatalogURLEntry(raw: raws[2], status: .invalid(.empty)),
      CatalogURLEntry(raw: raws[3], status: .invalid(.hasCredentials)),
      CatalogURLEntry(raw: raws[4], status: .duplicate(firstIndex: 0)),
      CatalogURLEntry(raw: raws[5], status: .usable(other)),
      CatalogURLEntry(raw: raws[6], status: .duplicate(firstIndex: 0)),
    ])
  }

  @Test("주소 문제 항목끼리는 같은 글자여도 중복으로 보지 않는다")
  func invalidEntriesAreNotDuplicates() {
    let raws = ["http://example.com/c.json", "http://example.com/c.json", ""]
    #expect(CatalogURLList.entries(raws).map(\.status) == [
      .invalid(.notHTTPS),
      .invalid(.notHTTPS),
      .invalid(.empty),
    ])
  }

  @Test("같은 문자열이 두 번 있으면 뒤는 처음 인덱스를 가리킨다")
  func sameStringTwice() throws {
    let raw = "https://example.com/c.json"
    let url = try #require(DownloadURL(raw))
    #expect(CatalogURLList.entries([raw, raw]).map(\.status) == [.usable(url), .duplicate(firstIndex: 0)])
  }

  @Test("빈 목록은 빈 상태")
  func empty() {
    #expect(CatalogURLList.entries([]).isEmpty)
  }

  @Test("같은 카탈로그인 첫 항목의 인덱스. 주소 문제 항목은 비교하지 않는다")
  func indexOfSameCatalog() throws {
    let raws = [
      "http://example.com/c.json",
      "https://other.example/c.json",
      "https://Example.com/c.json",
      "https://example.com/c.json",
    ]
    let url = try #require(DownloadURL("https://example.com:443/c.json#x"))
    let missing = try #require(DownloadURL("https://example.com/C.json"))

    #expect(CatalogURLList.indexOfSameCatalog(as: url, in: raws) == 2)
    #expect(CatalogURLList.indexOfSameCatalog(as: missing, in: raws) == nil)
    #expect(CatalogURLList.indexOfSameCatalog(as: url, in: []) == nil)
  }

  @Test(
    "저장 문자열을 다시 DownloadURL 로 읽으면 같은 URL 이다 (공백·한글 경로·한글 호스트 포함)",
    arguments: [
      "  https://example.com/catalog.json \n",
      "https://example.com/빌드 카탈로그.json",
      "https://예시.com/c.json?x=1#top",
      "HTTPS://Example.COM:8443/a%20b.json",
    ]
  )
  func storedStringRoundTrip(raw: String) throws {
    let url = try #require(DownloadURL(raw))
    let stored = CatalogURLList.storedString(for: url)

    #expect(stored == url.url.absoluteString)
    #expect(DownloadURL(stored) == url)
    #expect(!stored.contains(" "))
  }
}
