import Foundation

/// 녹화 파일 이름 (순수). 규칙은 `ScreenshotFileName` 과 같고(정리·시각·번호) 확장자만 "mov" 다
/// (simctl recordVideo 는 확장자와 관계없이 QuickTime 으로 쓴다, 측정). 녹화를 허용하는 기기 규칙은 따로 두지 않고
/// `VirtualDevice.screenshotAvailability` 를 함께 쓴다 (켜진 기기만).
public struct RecordingFileName: Hashable, Sendable {
  /// 번호·확장자를 뺀 이름. 같은 입력의 `ScreenshotFileName.stem` 과 같다.
  public let stem: String
  public static let fileExtension = "mov"
  /// 번호 없는 이름(1)부터 " 99" 까지.
  public static let maxAttempts = ScreenshotFileName.maxAttempts

  /// `startedAt` 은 "녹화"를 누른 시각.
  public init(deviceName: String, runtimeName: String, startedAt date: Date, timeZone: TimeZone) {
    self.stem = ScreenshotFileName(deviceName: deviceName, runtimeName: runtimeName, takenAt: date, timeZone: timeZone)
      .stem
  }

  /// attempt 1 → "<stem>.mov", 2...maxAttempts → "<stem> <n>.mov", 그 밖은 nil.
  public func fileName(attempt: Int) -> String? {
    switch attempt {
    case 1: "\(self.stem).\(Self.fileExtension)"
    case 2 ... Self.maxAttempts: "\(self.stem) \(attempt).\(Self.fileExtension)"
    default: nil
    }
  }
}
