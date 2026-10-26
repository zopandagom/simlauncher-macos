import Foundation
import Testing
@testable import Core

struct ScreenshotFileNameTests {
  /// 2026-10-25 05:21:33 UTC = 14:21:33 Asia/Seoul.
  static let takenAt = Date(timeIntervalSince1970: 1_792_905_693)
  static let seoul = TimeZone(identifier: "Asia/Seoul") ?? .gmt
  static let folder = URL(filePath: "/Users/someone/Pictures/SimLauncher/", directoryHint: .isDirectory)

  static func name(_ device: String, runtime: String = "iOS 26.5") -> ScreenshotFileName {
    ScreenshotFileName(deviceName: device, runtimeName: runtime, takenAt: self.takenAt, timeZone: self.seoul)
  }

  /// 번호 없는 파일 이름.
  static func fileName(_ device: String, runtime: String = "iOS 26.5") -> String {
    self.name(device, runtime: runtime).fileName(attempt: 1) ?? ""
  }

  /// 파일 이름이 저장 폴더 바로 안의 숨김 아닌 한 단계 이름인지.
  static func expectContained(_ fileName: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(!fileName.contains("/"), sourceLocation: sourceLocation)
    #expect(!fileName.contains(":"), sourceLocation: sourceLocation)
    #expect(
      !fileName.unicodeScalars.contains { $0.properties.generalCategory == .control },
      sourceLocation: sourceLocation
    )
    #expect(!fileName.unicodeScalars.starts(with: ".".unicodeScalars), sourceLocation: sourceLocation)
    #expect(fileName != "." && fileName != "..", sourceLocation: sourceLocation)
    let file = Self.folder.appending(path: fileName, directoryHint: .notDirectory)
    #expect(
      file.standardizedFileURL.deletingLastPathComponent().path(percentEncoded: false)
        == Self.folder.path(percentEncoded: false),
      sourceLocation: sourceLocation
    )
  }

  @Test("기본 형식: 기기 이름 (런타임 이름) 날짜 시각.png")
  func basicFormat() {
    #expect(Self.fileName("iPhone 17 Pro Max") == "iPhone 17 Pro Max (iOS 26.5) 2026-10-25 14.21.33.png")
  }

  @Test("같은 순간도 시간대에 따라 시각이 다르고, 날짜·시각은 0 으로 채운다")
  func timeZoneAndPadding() {
    let utc = ScreenshotFileName(deviceName: "iPad", runtimeName: "iOS 26.5", takenAt: Self.takenAt, timeZone: .gmt)
    #expect(utc.stem == "iPad (iOS 26.5) 2026-10-25 05.21.33")
    #expect(Self.name("iPad").stem == "iPad (iOS 26.5) 2026-10-25 14.21.33")

    // 2027-01-02 03:04:05 UTC.
    let early = Date(timeIntervalSince1970: 1_798_859_045)
    let padded = ScreenshotFileName(deviceName: "iPad", runtimeName: "iOS 26.5", takenAt: early, timeZone: .gmt)
    #expect(padded.stem == "iPad (iOS 26.5) 2027-01-02 03.04.05")
  }

  @Test("경로 구분자와 콜론은 - 로 바꾸고, 저장 폴더 밖을 가리키지 않는다")
  func pathSeparators() {
    #expect(Self.fileName("a/b:c") == "a-b-c (iOS 26.5) 2026-10-25 14.21.33.png")
    #expect(Self.fileName("x", runtime: "iOS/26:5") == "x (iOS-26-5) 2026-10-25 14.21.33.png")
    for device in ["../../etc", "/etc/passwd", "..", "a/../../b", "~/x"] {
      Self.expectContained(Self.fileName(device))
    }
    #expect(Self.fileName("../../etc") == "---..-etc (iOS 26.5) 2026-10-25 14.21.33.png")
  }

  @Test("제어 문자·줄 구분자·방향 제어 문자는 - 로 바꾼다")
  func controlCharacters() {
    #expect(Self.name("a\nb\tc\u{0}d\u{7F}e").stem.hasPrefix("a-b-c-d-e ("))
    #expect(Self.name("a\u{2028}b\u{2029}c").stem.hasPrefix("a-b-c ("))
    #expect(Self.name("a\u{202E}b\u{200F}c\u{2066}d\u{061C}e").stem.hasPrefix("a-b-c-d-e ("))
    #expect(Self.name("x", runtime: "iOS\n26").stem.hasPrefix("x (iOS-26) "))
    Self.expectContained(Self.fileName("\n\u{0}\u{202E}gnp.exe"))
  }

  @Test("앞뒤 공백을 빼고, 맨 앞의 점은 하나씩 - 로 바꾼다")
  func leadingDotsAndWhitespace() {
    #expect(Self.name("  iPhone  ").stem.hasPrefix("iPhone ("))
    #expect(Self.name(".").stem.hasPrefix("- ("))
    #expect(Self.name("..").stem.hasPrefix("-- ("))
    #expect(Self.name(".hidden").stem.hasPrefix("-hidden ("))
    #expect(Self.name(" .hidden").stem.hasPrefix("-hidden ("))
    #expect(Self.name("a.b.").stem.hasPrefix("a.b. ("))
    // 결합 문자가 붙은 점도 스칼라로 보아 바꾼다.
    Self.expectContained(Self.fileName(".\u{301}x"))
  }

  @Test("기기 이름이 비면 Simulator, 런타임 이름이 비면 괄호 부분을 뺀다")
  func emptyNames() {
    #expect(Self.fileName("   ") == "Simulator (iOS 26.5) 2026-10-25 14.21.33.png")
    #expect(Self.fileName("") == "Simulator (iOS 26.5) 2026-10-25 14.21.33.png")
    #expect(Self.fileName("iPhone", runtime: " ") == "iPhone 2026-10-25 14.21.33.png")
    #expect(Self.fileName("", runtime: "") == "Simulator 2026-10-25 14.21.33.png")
  }

  @Test("긴 이름은 글자 경계에서 바이트 상한까지 자르고, 가장 긴 파일 이름도 255 바이트 안이다")
  func length() throws {
    let long = ScreenshotFileName.sanitized(String(repeating: "가", count: 200), maxUTF8Bytes: 120)
    #expect(long == String(repeating: "가", count: 40))

    // 4 바이트 이모지는 상한 안에서 통째로만 남는다.
    #expect(ScreenshotFileName.sanitized("ab😀😀", maxUTF8Bytes: 7) == "ab😀")
    // 잘린 뒤 끝 공백은 뺀다.
    #expect(ScreenshotFileName.sanitized("abc def", maxUTF8Bytes: 4) == "abc")

    let longest = ScreenshotFileName(
      deviceName: String(repeating: "가", count: 200),
      runtimeName: String(repeating: "나", count: 100),
      takenAt: Self.takenAt,
      timeZone: Self.seoul
    )
    let fileName = try #require(longest.fileName(attempt: ScreenshotFileName.maxAttempts))
    #expect(fileName.utf8.count <= 255)
    #expect(longest.stem.hasPrefix(String(repeating: "가", count: 40) + " (" + String(repeating: "나", count: 13) + ") "))
  }

  @Test("상한 안의 결합 문자·ZWJ 이모지는 바뀌지 않는다")
  func graphemesKept() {
    let family = "👨‍👩‍👧"
    let combined = "e\u{301}"
    #expect(Self.name("\(family) \(combined)").stem.hasPrefix("\(family) \(combined) ("))
    #expect(Self.name("\(family) \(combined)").stem.unicodeScalars.contains("\u{200D}"))

    // 상한에 걸려도 ZWJ 이모지 한 글자를 중간에서 자르지 않는다 (한 글자 18 바이트).
    let cut = ScreenshotFileName.sanitized("a\(family)", maxUTF8Bytes: 10)
    #expect(cut == "a")
  }

  @Test("번호: 1 은 번호 없음, 2…99 는 확장자 앞에 번호, 그 밖은 nil")
  func attempts() {
    let name = Self.name("iPhone")
    #expect(name.fileName(attempt: 1) == "iPhone (iOS 26.5) 2026-10-25 14.21.33.png")
    #expect(name.fileName(attempt: 2) == "iPhone (iOS 26.5) 2026-10-25 14.21.33 2.png")
    #expect(name.fileName(attempt: 99) == "iPhone (iOS 26.5) 2026-10-25 14.21.33 99.png")
    #expect(name.fileName(attempt: 0) == nil)
    #expect(name.fileName(attempt: 100) == nil)
    #expect(name.fileName(attempt: -1) == nil)
  }
}
