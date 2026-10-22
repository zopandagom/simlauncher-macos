import Foundation
import Testing
@testable import PreferencesImpl

struct CatalogURLValueTests {
  @Test("문자열 배열은 순서·앞뒤 공백·빈 문자열 그대로")
  func stringArray() {
    let value: Any = [" https://a.example/c.json", "", "https://b.example/c.json"]
    #expect(CatalogURLValue.strings(from: value) == [" https://a.example/c.json", "", "https://b.example/c.json"])
  }

  @Test("섞인 배열은 문자열 항목만 순서대로")
  func mixedArray() {
    let value: Any = [
      "https://a.example/c.json",
      NSNumber(value: 1),
      ["k": "v"],
      "https://b.example/c.json",
      Data([1]),
    ] as [Any]
    #expect(CatalogURLValue.strings(from: value) == ["https://a.example/c.json", "https://b.example/c.json"])
  }

  @Test("NSArray 도 같게 읽는다")
  func nsArray() {
    let value: Any = NSArray(array: ["https://a.example/c.json", NSNumber(value: 2)])
    #expect(CatalogURLValue.strings(from: value) == ["https://a.example/c.json"])
  }

  @Test("문자열 하나는 한 항목 목록 (관리자가 -array 를 빠뜨린 경우)")
  func singleString() {
    #expect(CatalogURLValue.strings(from: "https://a.example/c.json") == ["https://a.example/c.json"])
    #expect(CatalogURLValue.strings(from: NSString(string: "x")) == ["x"])
  }

  @Test("빈 배열은 빈 목록")
  func emptyArray() {
    #expect(CatalogURLValue.strings(from: [Any]()).isEmpty)
  }

  @Test("값이 없거나 숫자·Data·사전이면 빈 목록")
  func otherValues() {
    #expect(CatalogURLValue.strings(from: nil).isEmpty)
    #expect(CatalogURLValue.strings(from: NSNumber(value: 3)).isEmpty)
    #expect(CatalogURLValue.strings(from: Data([1, 2])).isEmpty)
    #expect(CatalogURLValue.strings(from: ["k": "https://a.example/c.json"]).isEmpty)
  }
}
