import Foundation
import Testing
@testable import LauncherFeature

struct LauncherResourcesTests {
  @Test("리소스 번들의 원문 언어는 한국어다")
  func resourceBundleIsKorean() {
    #expect(Bundle.module.developmentLocalization == "ko")
  }

  @Test("String Catalog 가 리소스 번들의 한국어 문자열 표로 컴파일된다")
  func stringCatalogIsCompiledIntoResourceBundle() throws {
    let url = try #require(
      Bundle.module.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "ko")
    )
    let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
    #expect(table["iOS 시뮬레이터 기기 목록이 여기에 표시됩니다."] != nil)
  }
}
