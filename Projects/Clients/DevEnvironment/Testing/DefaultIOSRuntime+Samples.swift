import Core

/// 테스트·Example·Preview 가 함께 쓰는 기본 iOS 런타임 샘플.
public extension DefaultIOSRuntime {
  /// iOS 27.1 (24A94232). Xcode 27.1 의 iOS Simulator SDK 와 같다.
  static let sample = DefaultIOSRuntime(version: OSVersion(major: 27, minor: 1), build: "24A94232")
}
