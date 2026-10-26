import Core
import Foundation
import Testing

struct RecordingFileNameTests {
  /// 2026-10-25 05:21:33 UTC = 14:21:33 Asia/Seoul.
  static let startedAt = Date(timeIntervalSince1970: 1_792_905_693)
  static let seoul = TimeZone(identifier: "Asia/Seoul") ?? .gmt

  @Test("이름은 기기 이름 (런타임 이름) 날짜 시각.mov 이고, stem 은 같은 입력의 스크린샷 stem 과 같다")
  func formatMatchesScreenshot() {
    for device in ["iPhone 17 Pro Max", "a/b:c", "  .hidden", ""] {
      let name = RecordingFileName(
        deviceName: device,
        runtimeName: "iOS 26.5",
        startedAt: Self.startedAt,
        timeZone: Self.seoul
      )
      let screenshot = ScreenshotFileName(
        deviceName: device,
        runtimeName: "iOS 26.5",
        takenAt: Self.startedAt,
        timeZone: Self.seoul
      )
      #expect(name.stem == screenshot.stem)
    }
    let name = RecordingFileName(
      deviceName: "iPhone 17 Pro Max",
      runtimeName: "iOS 26.5",
      startedAt: Self.startedAt,
      timeZone: Self.seoul
    )
    #expect(name.fileName(attempt: 1) == "iPhone 17 Pro Max (iOS 26.5) 2026-10-25 14.21.33.mov")
    #expect(RecordingFileName.fileExtension == "mov")
  }

  @Test("번호: 1 은 번호 없음, 2…99 는 확장자 앞에 번호, 그 밖은 nil")
  func attempts() {
    let name = RecordingFileName(
      deviceName: "iPhone",
      runtimeName: "iOS 26.5",
      startedAt: Self.startedAt,
      timeZone: Self.seoul
    )
    #expect(RecordingFileName.maxAttempts == 99)
    #expect(name.fileName(attempt: 1) == "iPhone (iOS 26.5) 2026-10-25 14.21.33.mov")
    #expect(name.fileName(attempt: 2) == "iPhone (iOS 26.5) 2026-10-25 14.21.33 2.mov")
    #expect(name.fileName(attempt: 99) == "iPhone (iOS 26.5) 2026-10-25 14.21.33 99.mov")
    #expect(name.fileName(attempt: 0) == nil)
    #expect(name.fileName(attempt: 100) == nil)
  }
}
