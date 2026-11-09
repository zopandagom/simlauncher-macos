import AppLogInterface
import Core
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
    for platform in [AppLogTarget.Platform.iOS, .android] {
      let states = DeviceLogTextCatalog.states.map { DeviceLogText.state($0, platform: platform) }
      #expect(Set(states).count == states.count)
      #expect(DeviceLogText.state(.ended(.replaced), platform: platform).contains("다시 설치·실행"))
    }
    #expect(DeviceLogText.shortState(.ended(.deviceShutDown)) == DeviceLogText.shortState(.ended(.appExited)))
  }

  @Test("Android 세션의 기기 꺼짐은 연결 끊김도 말하고, 그 밖의 상태 글자는 iOS 와 같다")
  func androidStateTexts() {
    #expect(DeviceLogText.state(.ended(.deviceShutDown), platform: .iOS) == "끝남 — 기기가 꺼졌습니다")
    #expect(DeviceLogText.state(.ended(.deviceShutDown), platform: .android) == "끝남 — 기기가 꺼졌거나 연결이 끊겼습니다")
    for state in DeviceLogTextCatalog.states where state != .ended(.deviceShutDown) {
      #expect(DeviceLogText.state(state, platform: .android) == DeviceLogText.state(state, platform: .iOS))
    }
  }

  @Test("다시 실행 실패 문구는 케이스마다 다르고, 개발 도구 문구만 플랫폼별이다 (iOS 는 Xcode, Android 는 Android 도구)")
  func relaunchFailureTexts() {
    for platform in [AppLogTarget.Platform.iOS, .android] {
      let texts = DeviceLogTextCatalog.errors.map { DeviceLogText.relaunchFailed($0, platform: platform) }
      #expect(Set(texts).count == texts.count)
    }
    #expect(DeviceLogText.relaunchFailed(.developerToolsUnavailable, platform: .iOS).contains("Xcode"))
    let android = DeviceLogText.relaunchFailed(.developerToolsUnavailable, platform: .android)
    #expect(android.contains("Android 도구"))
    #expect(!android.contains("Xcode"))
    for error in DeviceLogTextCatalog.errors where error != .developerToolsUnavailable {
      let ios = DeviceLogText.relaunchFailed(error, platform: .iOS)
      #expect(DeviceLogText.relaunchFailed(error, platform: .android) == ios)
    }
    #expect(
      DeviceLogText.relaunchFailed(.deviceUnavailable(.folderMissing), platform: .android)
        == DeviceLogText.relaunchFailed(.deviceUnavailable(.unsupportedName), platform: .android)
    )
  }

  @Test("여러 줄 print 안내는 실측대로 줄마다 따로 걸러진다고 말한다")
  func multilineGuide() {
    #expect(DeviceLogText.filterHelp(platform: .iOS).contains("여러 줄 print 는 줄마다 따로 걸러집니다"))
  }

  @Test("Android 필터 안내는 iOS 머리말·print 를 말하지 않고, '시작' 이 태그부터라고 말한다")
  func androidFilterGuide() {
    let help = DeviceLogText.filterHelp(platform: .android)
    #expect(help.contains("태그부터"))
    #expect(!help.contains("print"))
    #expect(!help.contains("NSLog"))
  }
}

/// 문구 함수가 돌려주는 값과 그 카탈로그 키.
enum DeviceLogTextCatalog {
  static let states: [AppLogSessionState] = [
    .receiving, .ended(.appExited), .ended(.deviceShutDown), .ended(.replaced), .ended(.stopped),
  ]

  static let errors: [AppLogLaunchError] = [
    .developerToolsUnavailable, .deviceNotFound, .deviceNotBooted, .appNotInstalled, .appLaunchFailed, .commandFailed,
    .sessionNotFound, .deviceUnavailable(.folderMissing), .noLauncherActivity, .adbUnavailable,
  ]

  /// 보간 없는 문구. 카탈로그 키와 값이 문구 그대로다.
  static var plainTexts: [String] {
    var texts = [
      DeviceLogText.defaultWindowTitle, DeviceLogText.appPickerLabel, DeviceLogText.shortState(.ended(.appExited)),
      DeviceLogText.relaunchButton, DeviceLogText.relaunchHelp, DeviceLogText.noSessions,
      DeviceLogText.noSessionsGuide, DeviceLogText.noMatchingLines, DeviceLogText.kindLabel,
      DeviceLogText.conditionPrompt, DeviceLogText.excludeToggle, DeviceLogText.excludeHelp,
      DeviceLogText.removeCondition, DeviceLogText.addCondition, DeviceLogText.caseSensitiveToggle,
      DeviceLogText.invalidRegex, DeviceLogText.filterHelp(platform: .iOS),
      DeviceLogText.filterHelp(platform: .android), DeviceLogText.pauseButton, DeviceLogText.resumeButton,
      DeviceLogText.followToggle, DeviceLogText.followHelp, DeviceLogText.clearButton, DeviceLogText.clearHelp,
    ]
    texts += self.states.map { DeviceLogText.state($0, platform: .iOS) }
    texts.append(DeviceLogText.state(.ended(.deviceShutDown), platform: .android))
    texts += self.errors.map { DeviceLogText.relaunchFailed($0, platform: .iOS) }
    texts.append(DeviceLogText.relaunchFailed(.developerToolsUnavailable, platform: .android))
    texts += LogFilter.Kind.allCases.map(DeviceLogText.kind)
    texts += [
      DeviceLogText.savedFiltersMenu, DeviceLogText.noSavedFilters, DeviceLogText.saveCurrentFilter,
      DeviceLogText.deleteMenu, DeviceLogText.saveSheetTitle, DeviceLogText.saveNameLabel, DeviceLogText.saveButton,
      DeviceLogText.cancelButton, DeviceLogText.replaceMessage, DeviceLogText.replaceButton,
    ]
    texts += [LogFilterSaveBlock.locked, .emptyFilter, .invalidRegex].map(DeviceLogText.saveBlocked)
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
      FormatSample(
        key: "조건은 %lld개까지 저장할 수 있습니다.", arguments: [SavedLogFilter.maxConditions],
        text: DeviceLogText.saveBlocked(.tooManyConditions)
      ),
      FormatSample(
        key: "조건 글자는 %lld자까지 저장할 수 있습니다.", arguments: [SavedLogFilter.maxTextLength],
        // 화면 문구는 천 단위 구분("1,000")이 붙고 String(format:) 은 붙이지 않아 구분 기호만 뺀다.
        text: DeviceLogText.saveBlocked(.textTooLong).replacingOccurrences(of: ",", with: "")
      ),
      FormatSample(
        key: "저장된 필터는 %lld개까지입니다.", arguments: [SavedLogFilter.maxCount],
        text: DeviceLogText.savedFilterLimit
      ),
      FormatSample(
        key: "이름은 %lld자까지 쓸 수 있습니다.", arguments: [SavedLogFilter.maxNameLength],
        text: DeviceLogText.nameTooLong
      ),
      FormatSample(
        key: "‘%@’ 필터가 이미 있습니다", arguments: ["Errors"], text: DeviceLogText.replaceTitle(existingName: "Errors")
      ),
    ]
  }
}
