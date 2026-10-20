import Core
import Foundation

/// 테스트·Example·Preview 가 함께 쓰는 Xcode 샘플.
public extension XcodeInstallation {
  /// `/Applications/Xcode.app`, 27.1.
  static let sample = XcodeInstallation(
    bundleURL: URL(filePath: "/Applications/Xcode.app", directoryHint: .isDirectory),
    version: OSVersion(major: 27, minor: 1)
  )

  /// `/Applications/Xcode-beta.app`, 27.2.
  static let beta = XcodeInstallation(
    bundleURL: URL(filePath: "/Applications/Xcode-beta.app", directoryHint: .isDirectory),
    version: OSVersion(major: 27, minor: 2)
  )
}
