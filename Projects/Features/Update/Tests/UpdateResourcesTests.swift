import Core
import Foundation
import Testing
import UpdateCheckInterface
@testable import UpdateFeature

struct UpdateResourcesTests {
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
    let texts = UpdateTextCatalog.plainTexts
    for text in texts {
      #expect(table[text] == text, "\(text)")
    }
    // 코드의 키가 카탈로그 키와 어긋나면 코드 문자열로 서식을 만들어 겉보기에 멀쩡하므로, 표의 값으로 만든 문구와 비교한다.
    let formats = UpdateTextCatalog.formatSamples
    for sample in formats {
      #expect(table[sample.key] == sample.key, "\(sample.key)")
      #expect(String(format: table[sample.key] ?? "", arguments: sample.arguments) == sample.text, "\(sample.key)")
    }
    var keys = Set(texts)
    keys.formUnion(formats.map(\.key))
    #expect(keys == Set(table.keys))
  }
}

/// 문구 함수가 돌려주는 값.
struct UpdateTextTests {
  @Test("모든 문구와 모든 실패 케이스의 문구가 비어 있지 않은 한국어다")
  func textsAreNonEmptyKorean() {
    var texts = UpdateTextCatalog.plainTexts + UpdateTextCatalog.formatSamples.map(\.text)
    texts += UpdateTextCatalog.errors.map(UpdateText.message(for:))
    for text in texts {
      #expect(!text.isEmpty)
      #expect(text.unicodeScalars.contains { (0xAC00 ... 0xD7A3).contains($0.value) }, "\(text)")
    }
  }

  @Test("서버가 답한 실패와 닿지 못한 실패는 서로 다른 문구이고, 그 밖 실패·취소·저장소 없음은 같은 일반 문구다")
  func errorTextsDiffer() {
    let distinct: [UpdateCheckError] = [
      .offline, .timedOut, .connectionFailed, .refused, .notFound, .httpStatus(502), .unexpectedResponse, .failed,
    ]
    let texts = distinct.map(UpdateText.message(for:))
    #expect(Set(texts).count == texts.count)
    #expect(UpdateText.message(for: .cancelled) == UpdateText.message(for: .failed))
    #expect(UpdateText.message(for: .notConfigured) == UpdateText.message(for: .failed))
  }

  @Test("거절은 원인을 단정하지 않고 프록시·방화벽 확인과 다시 시도를 안내한다")
  func refusedText() {
    let text = UpdateText.message(for: .refused)
    #expect(text.contains("프록시·방화벽"))
    #expect(text.contains("githubusercontent.com"))
    #expect(text.contains("다운로드 페이지"))
    #expect(!text.contains("60"))
    #expect(!text.contains("api.github.com"))
  }

  @Test("업데이트 문구 어디에도 GitHub API 주소나 시간당 한도가 없다")
  func noAPIOrRateLimitText() {
    let texts = UpdateTextCatalog.plainTexts + UpdateTextCatalog.errors.map(UpdateText.message(for:))
    for text in texts {
      #expect(!text.contains("api.github.com"), "\(text)")
      #expect(!text.contains("시간당"), "\(text)")
    }
  }

  @Test("404 문구는 최신 릴리스의 버전 정보를 찾지 못했다고 안내한다")
  func notFoundText() {
    #expect(UpdateText.message(for: .notFound).contains("버전 정보"))
  }

  @Test("그 밖 HTTP 상태는 상태 번호를 보인다")
  func httpStatusText() {
    #expect(UpdateText.message(for: .httpStatus(502)).contains("HTTP 502"))
  }

  @Test("버전은 3자리로 정규화된 값으로 보인다 (응답 원문이 아니다)")
  func versionsAreNormalized() throws {
    let tagged = try #require(AppVersion("v1.3"))
    #expect(UpdateText.banner(tagged, current: v120) == "새 버전이 나왔습니다: SimLauncher 1.3.0 (지금 1.2.0)")
    #expect(UpdateText.newerTitle(tagged) == "새 버전이 나왔습니다: SimLauncher 1.3.0")
  }

  @Test("창 제목은 메뉴 항목에서 말줄임표를 뺀 이름이다")
  @MainActor
  func windowTitle() {
    #expect(UpdateCheckView.windowTitle == "업데이트 확인")
    #expect(UpdateText.menuItem == UpdateCheckView.windowTitle + "…")
  }
}

/// 문구 함수가 돌려주는 값과 그 카탈로그 키.
enum UpdateTextCatalog {
  /// 모든 실패 케이스 (HTTP 상태는 대표 하나).
  static let errors: [UpdateCheckError] = [
    .notConfigured, .offline, .timedOut, .connectionFailed, .refused, .notFound, .httpStatus(502),
    .unexpectedResponse, .failed, .cancelled,
  ]

  /// 보간 없는 문구. 카탈로그 키와 값이 문구 그대로다.
  static var plainTexts: [String] {
    var texts = [
      UpdateText.menuItem, UpdateText.windowTitle, UpdateText.checking, UpdateText.checkingCaption,
      UpdateText.unavailable, UpdateText.skippedNote, UpdateText.currentUnknown, UpdateText.latestUnrecognized,
      UpdateText.failedTitle, UpdateText.openDownloadPageButton, UpdateText.skipVersionButton,
      UpdateText.retryButton, UpdateText.closeButton, UpdateText.dismissBannerLabel,
    ]
    // HTTP 상태 문구만 보간이 들어 있다 (formatSamples). 같은 문구를 쓰는 케이스는 한 번만 넣는다.
    let plainErrors = self.errors.filter {
      if case .httpStatus = $0 {
        false
      } else {
        true
      }
    }
    for text in plainErrors.map(UpdateText.message(for:)) where !texts.contains(text) {
      texts.append(text)
    }
    return texts
  }

  struct FormatSample {
    let key: String
    let arguments: [any CVarArg]
    /// 같은 인자로 문구 함수가 돌려준 값.
    let text: String
  }

  /// 보간이 든 키와, 표의 값에 `arguments` 를 넣으면 나와야 하는 문구.
  static var formatSamples: [FormatSample] {
    [
      FormatSample(key: "새 버전이 나왔습니다: SimLauncher %@", arguments: ["1.3.0"], text: UpdateText.newerTitle(v130)),
      FormatSample(key: "지금 쓰는 버전: %@", arguments: ["1.2.0"], text: UpdateText.currentLine(v120)),
      FormatSample(key: "최신 버전을 쓰고 있습니다 (SimLauncher %@).", arguments: ["1.2.0"], text: UpdateText.upToDate(v120)),
      FormatSample(
        key: "GitHub 이 요청을 처리하지 못했습니다 (HTTP %lld). 잠시 뒤 다시 시도하세요.", arguments: [502],
        text: UpdateText.message(for: .httpStatus(502))
      ),
      FormatSample(
        key: "새 버전이 나왔습니다: SimLauncher %@ (지금 %@)", arguments: ["1.3.0", "1.2.0"],
        text: UpdateText.banner(v130, current: v120)
      ),
    ]
  }
}
