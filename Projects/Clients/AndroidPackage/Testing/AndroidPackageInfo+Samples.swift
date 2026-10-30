import Core
import Foundation

/// 테스트·Example·Preview 가 함께 쓰는 샘플 apk 정보. `location` 은 고정 경로라 실제로 읽지 않는 Fake 에서만 쓴다.
public extension AndroidPackageInfo {
  /// 기본값: 패키지 `com.example.sample`, minSdk 24, 네이티브 코드 없음 (어느 기기 ABI 에도, API 24 이상 기기에 설치할 수 있다),
  /// 위치 `/tmp/Sample.apk`.
  /// - Parameter packageName: `AndroidPackageName` 형식이어야 한다 (아니면 멈춘다).
  static func sample(
    packageName: String = "com.example.sample",
    minSDK: AndroidMinSDK = .level(24),
    nativeABIs: Set<String> = [],
    location: URL = URL(filePath: "/tmp/Sample.apk", directoryHint: .notDirectory)
  ) -> AndroidPackageInfo {
    guard let name = AndroidPackageName(packageName) else {
      preconditionFailure("샘플 패키지 이름이 AndroidPackageName 형식이 아니다: \(packageName)")
    }
    return AndroidPackageInfo(location: location, packageName: name, minSDK: minSDK, nativeABIs: nativeABIs)
  }
}
