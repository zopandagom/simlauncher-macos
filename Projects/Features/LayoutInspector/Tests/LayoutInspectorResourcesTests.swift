import Foundation
import Testing
@testable import LayoutInspectorFeature

struct LayoutInspectorResourcesTests {
  @Test("리소스 번들의 원문 언어는 한국어다")
  func resourceBundleIsKorean() {
    #expect(Bundle.module.developmentLocalization == "ko")
  }

  @Test("화면의 모든 문구가 String Catalog 에서 한국어 값으로 컴파일되고, 그 밖의 키는 없다")
  func everyTextIsInCompiledKoreanTable() throws {
    let url = try #require(
      Bundle.module.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "ko")
    )
    let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
    for text in LayoutInspectorTextCatalog.plainTexts {
      #expect(table[text] == text, "\(text)")
    }
    // 코드의 키가 카탈로그 키와 어긋나면 코드 문자열로 서식을 만들어 겉보기에 멀쩡하므로, 표의 값으로 만든 문구와 비교한다.
    for sample in LayoutInspectorTextCatalog.formatSamples {
      #expect(table[sample.key] == sample.key, "\(sample.key)")
      #expect(String(format: table[sample.key] ?? "", arguments: sample.arguments) == sample.text, "\(sample.key)")
    }
    var keys = Set(LayoutInspectorTextCatalog.plainTexts)
    keys.formUnion(LayoutInspectorTextCatalog.formatSamples.map(\.key))
    #expect(keys == Set(table.keys))
  }

  @Test("모든 문구가 비어 있지 않은 한국어다")
  func textsAreKorean() {
    let texts = LayoutInspectorTextCatalog.plainTexts + LayoutInspectorTextCatalog.formatSamples.map(\.text)
    for text in texts {
      #expect(!text.isEmpty)
      #expect(text.unicodeScalars.contains { (0xAC00 ... 0xD7A3).contains($0.value) }, "\(text)")
    }
  }

  @Test("실패 분류마다 다른 문구이고, 기기 쪽 다음 할 일을 말한다")
  func failureTexts() {
    let texts = LayoutInspectorFailure.allCases.map(LayoutInspectorText.failure)
    #expect(Set(texts).count == texts.count)
    #expect(LayoutInspectorText.failure(.displayOff).contains("전원 버튼"))
    #expect(LayoutInspectorText.failure(.automationBusy).contains("UI 테스트"))
    #expect(LayoutInspectorText.failure(.screenNotIdle).contains("화면이 멈춘 뒤"))
  }
}

/// 문구 함수가 돌려주는 값과 그 카탈로그 키.
enum LayoutInspectorTextCatalog {
  static var plainTexts: [String] {
    [
      LayoutInspectorText.refreshButton, LayoutInspectorText.refreshHelp, LayoutInspectorText.retryButton,
      LayoutInspectorText.reading, LayoutInspectorText.preparing, LayoutInspectorText.canvasAccessibilityLabel,
      LayoutInspectorText.noNodes, LayoutInspectorText.systemScreen, LayoutInspectorText.stackTitle,
      LayoutInspectorText.detailTitle, LayoutInspectorText.typeLabel, LayoutInspectorText.identifierLabel,
      LayoutInspectorText.textLabel, LayoutInspectorText.descriptionLabel, LayoutInspectorText.widthLabel,
      LayoutInspectorText.heightLabel, LayoutInspectorText.noPickGuide, LayoutInspectorText.densityUnavailable,
    ] + LayoutInspectorFailure.allCases.map(LayoutInspectorText.failure)
  }

  struct FormatSample {
    let key: String
    let arguments: [any CVarArg]
    /// 같은 인자로 문구 함수가 돌려준 값.
    let text: String
  }

  static var formatSamples: [FormatSample] {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let time = date.formatted(date: .omitted, time: .standard)
    return [
      FormatSample(
        key: "%@ 레이아웃",
        arguments: ["Pixel 9"],
        text: LayoutInspectorText.windowTitle(deviceName: "Pixel 9")
      ),
      FormatSample(key: "마지막 갱신 %@", arguments: [time], text: LayoutInspectorText.lastUpdated(date)),
      FormatSample(key: "마지막 화면: %@", arguments: [time], text: LayoutInspectorText.lastScreen(date)),
    ]
  }
}
