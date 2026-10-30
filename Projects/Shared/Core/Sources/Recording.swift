import Foundation

/// 녹화 파일의 형식. 확장자는 내용과 맞춘다.
public enum RecordingContainer: Hashable, Sendable {
  /// iOS: simctl recordVideo 는 확장자와 관계없이 QuickTime 으로 쓴다 (측정).
  case quickTime
  /// Android: screenrecord 는 H.264 mp4 로 쓴다 (실측).
  case mpeg4

  public var fileExtension: String {
    switch self {
    case .quickTime: "mov"
    case .mpeg4: "mp4"
    }
  }
}

/// 녹화 파일 이름 (순수). 규칙은 `ScreenshotFileName` 과 같고(정리·시각·번호) 확장자만 `RecordingContainer` 로 정한다
/// (iOS "mov", Android "mp4"). 녹화를 허용하는 기기 규칙은 따로 두지 않고 iOS 는 `VirtualDevice.screenshotAvailability`,
/// Android 는 `AndroidVirtualDevice.appActionAvailability` 를 함께 쓴다 (켜진 기기만).
public struct RecordingFileName: Hashable, Sendable {
  /// 번호·확장자를 뺀 이름. 같은 입력의 `ScreenshotFileName.stem` 과 같다.
  public let stem: String
  /// 점 없는 확장자 (`container.fileExtension`).
  public let fileExtension: String
  /// 번호 없는 이름(1)부터 " 99" 까지.
  public static let maxAttempts = ScreenshotFileName.maxAttempts

  /// `startedAt` 은 "녹화"를 누른 시각. `container` 기본값은 iOS 의 QuickTime.
  public init(
    deviceName: String,
    runtimeName: String,
    startedAt date: Date,
    timeZone: TimeZone,
    container: RecordingContainer = .quickTime
  ) {
    self.stem = ScreenshotFileName(deviceName: deviceName, runtimeName: runtimeName, takenAt: date, timeZone: timeZone)
      .stem
    self.fileExtension = container.fileExtension
  }

  /// attempt 1 → "<stem>.<확장자>", 2...maxAttempts → "<stem> <n>.<확장자>", 그 밖은 nil.
  public func fileName(attempt: Int) -> String? {
    switch attempt {
    case 1: "\(self.stem).\(self.fileExtension)"
    case 2 ... Self.maxAttempts: "\(self.stem) \(attempt).\(self.fileExtension)"
    default: nil
    }
  }
}
