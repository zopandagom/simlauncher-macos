import Core
import Foundation

/// 테스트·Example·Preview 가 함께 쓰는 샘플 앱 정보. `location` 은 고정 경로라 실제로 읽지 않는 Fake 에서만 쓴다.
public extension AppBundleInfo {
  private static let sampleBundleID: AppBundleID = {
    guard let id = AppBundleID("com.example.sample") else {
      preconditionFailure("샘플 번들 ID 리터럴이 AppBundleID 형식이 아니다")
    }
    return id
  }()

  /// 번들 ID `com.example.sample`, 시뮬레이터용, arm64·x86_64, 최소 iOS 17.0. 어느 Mac·iOS 27 기기에도 설치할 수 있다.
  static let sample = AppBundleInfo(
    bundleID: Self.sampleBundleID,
    displayName: "샘플 앱",
    version: "1.0",
    build: "1",
    platforms: [.iOSSimulator],
    architectures: [.arm64, .x86_64],
    minimumOSVersion: OSVersion(major: 17),
    location: URL(filePath: "/tmp/SampleApp.app", directoryHint: .isDirectory)
  )

  /// 기기용 빌드 (`CFBundleSupportedPlatforms` 가 iPhoneOS, arm64). Core 판정이 `.notSimulatorBuild`.
  static let deviceBuild = Self.sample.with(platforms: [.iOS], architectures: [.arm64])

  /// x86_64 만 든 시뮬레이터 빌드. Apple 실리콘(arm64)에서 Core 판정이 `.missingArchitecture(.arm64)`.
  static let x86Only = Self.sample.with(platforms: [.iOSSimulator], architectures: [.x86_64])

  /// `.sample` 에서 최소 iOS 버전만 바꾼 값.
  static func requiring(_ version: OSVersion) -> AppBundleInfo {
    AppBundleInfo(
      bundleID: self.sample.bundleID,
      displayName: self.sample.displayName,
      version: self.sample.version,
      build: self.sample.build,
      platforms: self.sample.platforms,
      architectures: self.sample.architectures,
      minimumOSVersion: version,
      location: self.sample.location
    )
  }

  private func with(platforms: Set<AppBundlePlatform>?, architectures: Set<CPUArchitecture>) -> AppBundleInfo {
    AppBundleInfo(
      bundleID: self.bundleID,
      displayName: self.displayName,
      version: self.version,
      build: self.build,
      platforms: platforms,
      architectures: architectures,
      minimumOSVersion: self.minimumOSVersion,
      location: self.location
    )
  }
}
