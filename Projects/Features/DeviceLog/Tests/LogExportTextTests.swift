import AppLogInterface
import Core
import Foundation
import Testing
@testable import DeviceLogFeature

/// 내보낼 글 (`LogExportText`): 머리말 순서·문구, 플랫폼별 줄, 필터 표기, 줄 그대로, 영어 표.
struct LogExportTextTests {
  static let seoul = TimeZone(secondsFromGMT: 32400) ?? .gmt
  /// 2027-01-15 17:00:00 +09:00.
  static let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
  /// 2027-01-15 18:00:00 +09:00.
  static let exportedAt = Date(timeIntervalSince1970: 1_800_003_600)
  static let iosTarget = AppLogTarget.iOS(VirtualDevice.ID("5C0F3A2E-0000-4000-8000-000000000001"))
  static let androidTarget = AppLogTarget.android(AndroidVirtualDevice.ID("Pixel_9"))

  static func iosSession(
    appVersion: AppLogAppVersion? = AppLogAppVersion(version: "1.2", build: "34"),
    deviceOS: AppLogDeviceOS? = .iOS(runtimeName: "iOS 27.0"),
    state: AppLogSessionState = .receiving,
    appName: String = "LogProbe",
    deviceName: String = "iPhone 17 Pro"
  ) -> AppLogSessionSummary {
    AppLogSessionSummary(
      id: AppLogSessionID(UUID()), target: self.iosTarget, deviceName: deviceName, deviceOS: deviceOS,
      appID: "dev.simlauncher.logprobe", appName: appName, appVersion: appVersion, startedAt: self.startedAt,
      state: state
    )
  }

  static func androidSession(
    deviceOS: AppLogDeviceOS? = .android(apiLabel: "37.0"),
    state: AppLogSessionState = .receiving
  ) -> AppLogSessionSummary {
    AppLogSessionSummary(
      id: AppLogSessionID(UUID()), target: self.androidTarget, deviceName: "Pixel 9", deviceOS: deviceOS,
      appID: "com.example.app", appName: "com.example.app", appVersion: nil, startedAt: self.startedAt,
      state: state
    )
  }

  static func lines(_ texts: [String], from start: Int = 0) -> [VisibleLogLine] {
    texts.enumerated().map {
      VisibleLogLine(line: AppLogLine(index: start + $0.offset, text: $0.element), highlights: [])
    }
  }

  static func snapshot(
    _ session: AppLogSessionSummary,
    lines: [String] = ["first", "second"],
    totalCount: Int = 300,
    discarded: Int? = nil,
    hasCleared: Bool = false,
    isPaused: Bool = false,
    newWhilePaused: Int = 0,
    filter: LogFilter = LogFilter(),
    version: String? = "1.3.0 (45)"
  ) -> LogExportSnapshot {
    LogExportSnapshot(
      session: session, lines: Self.lines(lines), totalCount: totalCount, discarded: discarded, hasCleared: hasCleared,
      isPaused: isPaused, newWhilePaused: newWhilePaused, filter: filter, exportedAt: self.exportedAt,
      simLauncherVersion: version
    )
  }

  static func header(_ snapshot: LogExportSnapshot, bundle: Bundle = .module) -> [String] {
    LogExportText.header(snapshot, bundle: bundle, timeZone: self.seoul)
  }

  /// 포함 "network"(포함), 제외 "^heartbeat"(정규식), 대소문자 무시.
  static var sampleFilter: LogFilter {
    var filter = LogFilter()
    filter.setText("network", of: 0)
    filter.addCondition()
    filter.setText("^heartbeat", of: 1)
    filter.setKind(.regex, of: 1)
    filter.setExcluded(true, of: 1)
    return filter
  }

  // MARK: - 머리말

  @Test("iOS 세션의 머리말은 정해진 순서·문구로 나오고 줄마다 \\n 으로 끝난다")
  func iosHeaderKorean() async {
    let snapshot = Self.snapshot(
      Self.iosSession(), discarded: 5, hasCleared: true, isPaused: true, newWhilePaused: 7, filter: Self.sampleFilter
    )
    let text = await LogExportText.make(snapshot, timeZone: Self.seoul)
    #expect(text == """
    SimLauncher 앱 로그
    SimLauncher 버전: 1.3.0 (45)
    내보낸 시각: 2027-01-15 18:00:00 +09:00
    앱: LogProbe (dev.simlauncher.logprobe)
    앱 버전: 1.2 (34)
    기기: iPhone 17 Pro · iOS 27.0
    실행 시각: 2027-01-15 17:00:00 +09:00
    상태: 받는 중
    필터 (대소문자 무시):
    - 포함 · 포함: network
    - 제외 · 정규식: ^heartbeat
    줄: 보이는 2줄 / 전체 300줄
    버퍼가 차서 앞 5줄을 버렸습니다
    이 창에서 지운 줄은 빠졌습니다
    일시정지 중: 멈춘 지점까지의 줄입니다. 멈춘 뒤 받은 7줄은 빠졌습니다
    ----------------------------------------
    first
    second

    """)
  }

  @Test("Android 세션은 앱 버전 줄이 없고 기기 줄에 Android API 가 붙는다")
  func androidHeaderHasNoAppVersion() {
    let header = Self.header(Self.snapshot(Self.androidSession()))
    #expect(!header.contains { $0.hasPrefix("앱 버전:") })
    #expect(header.contains("기기: Pixel 9 · Android API 37.0"))
    #expect(header.contains("앱: com.example.app (com.example.app)"))
    #expect(header[3] == "앱: com.example.app (com.example.app)")
    #expect(header[4] == "기기: Pixel 9 · Android API 37.0")
  }

  @Test("SimLauncher 버전·앱 버전·기기 OS 를 모르면 알 수 없음/기기 이름만")
  func unknownValues() {
    let ios = Self.header(Self.snapshot(Self.iosSession(appVersion: nil, deviceOS: nil), version: nil))
    #expect(ios.contains("SimLauncher 버전: 알 수 없음"))
    #expect(ios.contains("앱 버전: 알 수 없음"))
    #expect(ios.contains("기기: iPhone 17 Pro"))
    let android = Self.header(Self.snapshot(Self.androidSession(deviceOS: nil)))
    #expect(android.contains("기기: Pixel 9"))
  }

  @Test("앱 버전은 버전·빌드 / 버전만 / 빌드만 / 둘 다 없음을 각각 적는다")
  func appVersionForms() {
    let cases: [(AppLogAppVersion, String)] = [
      (AppLogAppVersion(version: "1.2", build: "34"), "앱 버전: 1.2 (34)"),
      (AppLogAppVersion(version: "1.2", build: nil), "앱 버전: 1.2"),
      (AppLogAppVersion(version: nil, build: "34"), "앱 버전: (34)"),
      (AppLogAppVersion(version: nil, build: nil), "앱 버전: 알 수 없음"),
      (AppLogAppVersion(version: "", build: ""), "앱 버전: 알 수 없음"),
    ]
    for (version, expected) in cases {
      #expect(Self.header(Self.snapshot(Self.iosSession(appVersion: version))).contains(expected), "\(expected)")
    }
  }

  @Test("조건 글자가 모두 비면 필터: 없음")
  func emptyFilter() {
    var filter = LogFilter()
    filter.addCondition()
    filter.setKind(.regex, of: 1)
    filter.setCaseSensitive(true)
    let header = Self.header(Self.snapshot(Self.iosSession(), filter: filter))
    #expect(header.contains("필터: 없음"))
    #expect(!header.contains { $0.hasPrefix("필터 (") || $0.hasPrefix("- ") })
  }

  @Test("포함·제외·종류·대소문자를 줄마다 적고 빈 조건은 뺀다")
  func filterConditions() {
    var filter = LogFilter()
    filter.setText("Error", of: 0)
    filter.setKind(.prefix, of: 0)
    filter.addCondition()
    filter.addCondition()
    filter.setText("noise", of: 2)
    filter.setExcluded(true, of: 2)
    filter.setCaseSensitive(true)
    #expect(LogExportText.filter(filter, bundle: .module) == [
      "필터 (대소문자 구분):",
      "- 포함 · 시작: Error",
      "- 제외 · 포함: noise",
    ])
  }
}

// 구조체 본문 길이 상한(type_body_length) 때문에 나눈다. 같은 스위트다.
extension LogExportTextTests {
  @Test("조건 글자의 줄바꿈은 \\n·\\r 두 글자로 적는다")
  func conditionNewlineEscaped() {
    var filter = LogFilter()
    filter.setText("a\nb\r\nc\td\u{2028}e\u{85}f", of: 0)
    #expect(LogExportText.filter(filter, bundle: .module) == [
      "필터 (대소문자 무시):",
      "- 포함 · 포함: a\\nb\\r\\nc\\u{0009}d\\u{2028}e\\u{0085}f",
    ])
  }

  @Test("앱·기기 이름의 제어 문자·줄 구분자는 공백으로 바꿔 머리말 한 줄을 지킨다")
  func singleLineNames() {
    let session = Self.iosSession(appName: "Log\nProbe\u{2029}X", deviceName: "My\r\u{85}Phone\u{2028}")
    let header = Self.header(Self.snapshot(session))
    #expect(header.contains("앱: Log Probe X (dev.simlauncher.logprobe)"))
    #expect(header.contains("기기: My  Phone  · iOS 27.0"))
    #expect(header.allSatisfy { !$0.contains("\n") && !$0.contains("\r") })
  }

  @Test("일시정지(새 줄 0·1·2)·지움·버린 줄 표시는 해당할 때만 나온다")
  func pausedClearedDiscarded() {
    let plain = Self.header(Self.snapshot(Self.iosSession()))
    #expect(plain.last == "줄: 보이는 2줄 / 전체 300줄")
    let paused0 = Self.header(Self.snapshot(Self.iosSession(), isPaused: true, newWhilePaused: 0))
    #expect(paused0.last == "일시정지 중: 멈춘 지점까지의 줄입니다")
    let paused1 = Self.header(Self.snapshot(Self.iosSession(), isPaused: true, newWhilePaused: 1))
    #expect(paused1.last == "일시정지 중: 멈춘 지점까지의 줄입니다. 멈춘 뒤 받은 1줄은 빠졌습니다")
    let paused2 = Self.header(Self.snapshot(Self.iosSession(), isPaused: true, newWhilePaused: 2))
    #expect(paused2.last == "일시정지 중: 멈춘 지점까지의 줄입니다. 멈춘 뒤 받은 2줄은 빠졌습니다")
    let cleared = Self.header(Self.snapshot(Self.iosSession(), hasCleared: true))
    #expect(cleared.last == "이 창에서 지운 줄은 빠졌습니다")
    let discarded = Self.header(Self.snapshot(Self.iosSession(), discarded: 3))
    #expect(discarded.last == "버퍼가 차서 앞 3줄을 버렸습니다")
  }

  @Test("받은 줄이 없을 때 지우기를 누른 창은 지운 줄 표시가 없다 (지운 지점 -1)")
  func clearWithoutLinesHasNoClearedLine() {
    var window = DeviceLogWindow()
    let session = Self.iosSession()
    window.open()
    window.select(session.id)
    window.clear()
    let snapshot = LogExportSnapshot(
      window: window,
      session: session,
      exportedAt: Self.exportedAt,
      simLauncherVersion: nil
    )
    #expect(!snapshot.hasCleared)
    #expect(!Self.header(snapshot).contains("이 창에서 지운 줄은 빠졌습니다"))
  }

  @Test("보이는 줄은 번호 순으로 제어 문자를 그대로 담고 마지막 줄도 \\n 으로 끝난다")
  func linesVerbatim() async {
    let texts = ["\u{1B}[31mred\u{1B}[0m", "nul\u{0}bell\u{7}tab\tcr\rend", "", "한글 줄"]
    let text = await LogExportText.make(Self.snapshot(Self.iosSession(), lines: texts), timeZone: Self.seoul)
    let body = text.components(separatedBy: LogExportText.separator + "\n").last
    #expect(body == texts.map { $0 + "\n" }.joined())
    #expect(text.hasSuffix("한글 줄\n"))
    #expect(!text.contains("\r\n"))
    #expect(!text.hasPrefix("\u{FEFF}"))
  }

  @Test("받는 중과 끝난 이유를 화면 문구 그대로 적는다 (Android 기기 꺼짐 문구 포함)")
  func stateLine() {
    let states: [AppLogSessionState] = [
      .receiving, .ended(.appExited), .ended(.deviceShutDown), .ended(.replaced), .ended(.stopped),
    ]
    for state in states {
      let ios = Self.header(Self.snapshot(Self.iosSession(state: state)))
      #expect(ios.contains("상태: \(DeviceLogText.state(state, platform: .iOS))"))
      let android = Self.header(Self.snapshot(Self.androidSession(state: state)))
      #expect(android.contains("상태: \(DeviceLogText.state(state, platform: .android))"))
    }
    let android = Self.header(Self.snapshot(Self.androidSession(state: .ended(.deviceShutDown))))
    #expect(android.contains("상태: 끝남 — 기기가 꺼졌거나 연결이 끊겼습니다"))
  }

  /// 개수는 2 로 둔다: `String(localized:bundle:)` 의 복수형 규칙은 테스트 스킴의 지금 로케일(ko)을 따르므로 1 의 단수형은
  /// 여기서 보지 않는다 (en 복수형 갈림은 `DeviceLogEnglishPluralTests` 가 en 로케일로 본다).
  @Test("영어 표(en.lproj)로 만든 머리말 전체가 영어 문구다")
  func englishHeader() throws {
    let path = try #require(Bundle.module.path(forResource: "en", ofType: "lproj"))
    let english = try #require(Bundle(path: path))
    let snapshot = Self.snapshot(
      Self.iosSession(state: .ended(.appExited)), discarded: 2, hasCleared: true, isPaused: true, newWhilePaused: 2,
      filter: Self.sampleFilter
    )
    let header = Self.header(snapshot, bundle: english)
    #expect(header == [
      "SimLauncher App Log",
      "SimLauncher version: 1.3.0 (45)",
      "Exported: 2027-01-15 18:00:00 +09:00",
      "App: LogProbe (dev.simlauncher.logprobe)",
      "App version: 1.2 (34)",
      "Device: iPhone 17 Pro · iOS 27.0",
      "Launched: 2027-01-15 17:00:00 +09:00",
      "Status: Ended — the app quit",
      "Filter (case-insensitive):",
      "- Include · Contains: network",
      "- Exclude · Regex: ^heartbeat",
      "Lines: Showing 2 of 300 lines",
      "The buffer was full, so the first 2 lines were dropped",
      "Lines cleared in this window are not included",
      "Paused: lines up to the pause point. 2 lines received after pausing are not included",
    ])
    let unknown = Self.header(Self.snapshot(Self.iosSession(appVersion: nil), version: nil), bundle: english)
    #expect(unknown.contains("SimLauncher version: Unknown"))
    #expect(unknown.contains("App version: Unknown"))
    let android = Self.header(Self.snapshot(Self.androidSession(), isPaused: true), bundle: english)
    #expect(android.contains("Filter: None"))
    #expect(android.contains("Paused: lines up to the pause point"))
    var sensitive = LogFilter()
    sensitive.setText("x", of: 0)
    sensitive.setCaseSensitive(true)
    let sensitiveLines = LogExportText.filter(sensitive, bundle: english)
    #expect(sensitiveLines.first == "Filter (case-sensitive):")
    for line in header + unknown + android {
      #expect(!line.unicodeScalars.contains { (0xAC00 ... 0xD7A3).contains($0.value) }, "\(line)")
    }
  }
}
