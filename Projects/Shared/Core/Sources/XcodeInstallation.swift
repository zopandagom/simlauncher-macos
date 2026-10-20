import Foundation

/// 이 Mac 에 있는 Xcode 하나 (Impl 이 번들의 Info.plist 를 읽어 만든다).
public struct XcodeInstallation: Hashable, Sendable {
  /// `.app` 번들의 실제 경로 (Impl 이 realpath 로 만든 표준 형태, 예: /Applications/Xcode.app/).
  /// 같은 번들은 어느 경로(링크)로 찾아도 같은 값이 되어 Hashable 비교·중복 제거가 맞는다.
  public let bundleURL: URL
  /// CFBundleShortVersionString 을 `OSVersion(_:)` 으로 읽은 값.
  public let version: OSVersion

  public init(bundleURL: URL, version: OSVersion) {
    self.bundleURL = bundleURL
    self.version = version
  }

  /// `<bundleURL>/Contents/Developer`. provider 와 `DEVELOPER_DIR` 에 쓴다.
  public var developerDirectory: URL {
    self.bundleURL.appending(path: "Contents/Developer", directoryHint: .isDirectory)
  }
}
