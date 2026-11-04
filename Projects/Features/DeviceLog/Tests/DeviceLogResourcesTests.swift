import AppLogInterface
import Foundation
import Testing
@testable import DeviceLogFeature

struct DeviceLogResourcesTests {
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
    let texts = DeviceLogTextCatalog.plainTexts
    for text in texts {
      #expect(table[text] == text, "\(text)")
    }
    // 코드의 키가 카탈로그 키와 어긋나면 코드 문자열로 서식을 만들어 겉보기에 멀쩡하므로, 표의 값으로 만든 문구와 비교한다.
    let formats = DeviceLogTextCatalog.formatSamples
    for sample in formats {
      #expect(table[sample.key] == sample.key, "\(sample.key)")
      #expect(String(format: table[sample.key] ?? "", arguments: sample.arguments) == sample.text, "\(sample.key)")
    }
    var keys = Set(texts)
    keys.formUnion(formats.map(\.key))
    #expect(keys == Set(table.keys))
  }

  @Test("모든 문구가 비어 있지 않은 한국어다")
  func textsAreKorean() {
    let texts = DeviceLogTextCatalog.plainTexts + DeviceLogTextCatalog.formatSamples.map(\.text)
    for text in texts {
      #expect(!text.isEmpty)
      #expect(text.unicodeScalars.contains { (0xAC00 ... 0xD7A3).contains($0.value) }, "\(text)")
    }
  }

  @Test("끝남 이유마다 다른 상태 글자이고, 다시 설치·실행으로 끝난 세션은 SimLauncher 가 했다고 말한다")
  func endStateTexts() {
    let states = DeviceLogTextCatalog.states.map(DeviceLogText.state)
    #expect(Set(states).count == states.count)
    #expect(DeviceLogText.state(.ended(.replaced)).contains("다시 설치·실행"))
    #expect(DeviceLogText.shortState(.ended(.deviceShutDown)) == DeviceLogText.shortState(.ended(.appExited)))
  }

  @Test("여러 줄 print 안내는 실측대로 줄마다 따로 걸러진다고 말한다")
  func multilineGuide() {
    #expect(DeviceLogText.filterHelp.contains("여러 줄 print 는 줄마다 따로 걸러집니다"))
  }
}

/// 문구 함수가 돌려주는 값과 그 카탈로그 키.
enum DeviceLogTextCatalog {
  static let states: [AppLogSessionState] = [
    .receiving, .ended(.appExited), .ended(.deviceShutDown), .ended(.replaced), .ended(.stopped),
  ]

  static let errors: [AppLogLaunchError] = [
    .developerToolsUnavailable, .deviceNotFound, .deviceNotBooted, .appNotInstalled, .appLaunchFailed, .commandFailed,
    .sessionNotFound,
  ]

  /// 보간 없는 문구. 카탈로그 키와 값이 문구 그대로다.
  static var plainTexts: [String] {
    var texts = [
      DeviceLogText.defaultWindowTitle, DeviceLogText.appPickerLabel, DeviceLogText.shortState(.ended(.appExited)),
      DeviceLogText.relaunchButton, DeviceLogText.relaunchHelp, DeviceLogText.noSessions,
      DeviceLogText.noSessionsGuide, DeviceLogText.noMatchingLines, DeviceLogText.kindLabel,
      DeviceLogText.conditionPrompt, DeviceLogText.excludeToggle, DeviceLogText.excludeHelp,
      DeviceLogText.removeCondition, DeviceLogText.addCondition, DeviceLogText.caseSensitiveToggle,
      DeviceLogText.invalidRegex, DeviceLogText.filterHelp, DeviceLogText.pauseButton, DeviceLogText.resumeButton,
      DeviceLogText.followToggle, DeviceLogText.followHelp, DeviceLogText.clearButton, DeviceLogText.clearHelp,
    ]
    texts += self.states.map(DeviceLogText.state)
    texts += self.errors.map(DeviceLogText.relaunchFailed)
    texts += LogFilter.Kind.allCases.map(DeviceLogText.kind)
    return texts
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
        key: "%@ 로그", arguments: ["iPhone 17 Pro"], text: DeviceLogText.windowTitle(deviceName: "iPhone 17 Pro")
      ),
      FormatSample(
        key: "%@ · 시작 %@ · %@", arguments: ["LogProbe", time, DeviceLogText.receiving],
        text: DeviceLogText.sessionLabel(appName: "LogProbe", startedAt: date, state: .receiving)
      ),
      FormatSample(
        key: "보이는 %lld줄 / 전체 %lld줄", arguments: [12, 340], text: DeviceLogText.lineCounts(visible: 12, total: 340)
      ),
      FormatSample(key: "버퍼가 차서 앞 %lld줄을 버렸습니다", arguments: [5], text: DeviceLogText.discarded(5)),
      FormatSample(key: "새 줄 %lld", arguments: [7], text: DeviceLogText.newWhilePaused(7)),
    ]
  }
}
