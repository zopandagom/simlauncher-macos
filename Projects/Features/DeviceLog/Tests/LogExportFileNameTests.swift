import Foundation
import Testing
@testable import DeviceLogFeature

/// "저장…" 기본 파일 이름 (`LogExportFileName`).
struct LogExportFileNameTests {
  static let seoul = TimeZone(secondsFromGMT: 32400) ?? .gmt
  /// 2027-01-15 18:00:00 +09:00.
  static let date = Date(timeIntervalSince1970: 1_800_003_600)

  static func name(_ app: String, _ device: String) -> String {
    LogExportFileName.make(appName: app, deviceName: device, date: self.date, timeZone: self.seoul)
  }

  @Test("앱·기기 이름과 로컬 시각으로 SimLauncher-<앱>-<기기>-<시각>.txt 를 만든다")
  func plain() {
    #expect(Self.name("LogProbe", "iPhone 17 Pro") == "SimLauncher-LogProbe-iPhone_17_Pro-20270115-180000.txt")
    #expect(Self.name("com.example.app", "Pixel 9") == "SimLauncher-com.example.app-Pixel_9-20270115-180000.txt")
  }

  @Test("파일 이름에 못 쓰는 글자는 _ 로 바꾸고 이어진 _ 는 하나로 줄인다")
  func forbiddenCharacters() {
    #expect(LogExportFileName.part("a/b:c\\d*e?f\"g<h>i|j", fallback: "App") == "a_b_c_d_e_f_g_h_i_j")
    #expect(LogExportFileName.part("a//::b", fallback: "App") == "a_b")
  }

  @Test("제어 문자·줄 구분자·공백류도 _ 로 바꾼다")
  func controlAndWhitespace() {
    #expect(LogExportFileName
      .part("a\nb\tc\u{0}d\u{2028}e\u{2029}f\u{85}g\u{3000}h", fallback: "App") == "a_b_c_d_e_f_g_h")
    #expect(LogExportFileName.part("My  \t Phone", fallback: "Device") == "My_Phone")
  }

  @Test("앞뒤의 . _ - 를 뗀다 (숨김 파일·.. 방지)")
  func trimsDotsAndSeparators() {
    #expect(LogExportFileName.part("..hidden..", fallback: "App") == "hidden")
    #expect(LogExportFileName.part(" -_.app._- ", fallback: "App") == "app")
    #expect(LogExportFileName.part("a.b-c_d", fallback: "App") == "a.b-c_d")
  }

  @Test("정리한 결과가 비면 App·Device 로 둔다")
  func emptyFallsBack() {
    #expect(Self.name("", "") == "SimLauncher-App-Device-20270115-180000.txt")
    #expect(Self.name("...", "/ / /") == "SimLauncher-App-Device-20270115-180000.txt")
    #expect(Self.name("\n\t", "..") == "SimLauncher-App-Device-20270115-180000.txt")
  }

  @Test("긴 이름은 UTF-8 60바이트 안에서 글자 경계로 자르고 전체는 255바이트 이하다")
  func longNamesCutAtCharacterBoundary() {
    // 한글은 3바이트: 21자(63바이트) → 20자(60바이트).
    let korean = String(repeating: "가", count: 21)
    #expect(LogExportFileName.part(korean, fallback: "App") == String(repeating: "가", count: 20))
    // 결합된 가족 이모지(👨‍👩‍👧, 18바이트) 3개 + 1바이트 = 55바이트, 하나 더하면 73바이트 → 이모지를 쪼개지 않는다.
    let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
    let emoji = "a" + String(repeating: family, count: 4)
    let cut = LogExportFileName.part(emoji, fallback: "App")
    #expect(cut == "a" + String(repeating: family, count: 3))
    #expect(cut.utf8.count <= LogExportFileName.partByteLimit)
    // 자른 끝이 구분 문자면 다시 뗀다.
    let trailing = String(repeating: "a", count: 59) + "-bbbb"
    #expect(LogExportFileName.part(trailing, fallback: "App") == String(repeating: "a", count: 59))
    let longest = Self.name(String(repeating: "가", count: 100), String(repeating: "é", count: 100))
    #expect(longest.utf8.count <= 255)
    #expect(longest.utf8.count <= 153)
  }

  @Test("시각은 넘긴 시간대의 로컬 시각이다")
  func localTimestamp() {
    #expect(LogExportFileName.timestamp(Self.date, timeZone: Self.seoul) == "20270115-180000")
    #expect(LogExportFileName.timestamp(Self.date, timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt) == "20270115-090000")
    let newYork = TimeZone(secondsFromGMT: -5 * 3600) ?? .gmt
    #expect(LogExportFileName.timestamp(Self.date, timeZone: newYork) == "20270115-040000")
  }
}
