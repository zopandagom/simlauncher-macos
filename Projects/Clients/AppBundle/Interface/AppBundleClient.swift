import Core
import Foundation

/// 로컬 iOS 앱 번들(.app)을 읽는 Client. 파일을 고치거나 실행하지 않는다. (2-B 에서 zip 풀기를 더한다)
public protocol AppBundleClient: Sendable {
  /// 이 Mac 의 iOS 시뮬레이터가 실행하는 아키텍처. Apple 실리콘이면 arm64 (Rosetta 로 실행 중이어도), 아니면 x86_64.
  var hostArchitecture: CPUArchitecture { get }

  /// .app 의 Info.plist 와 실행 파일 헤더를 읽는다. 설치 가능 판정은 하지 않는다 (Core `installProblem`).
  /// 심볼릭 링크를 푼 실제 경로로 검사하고, 그 경로를 결과의 `location` 에 담는다.
  func inspect(_ url: URL) async throws(AppBundleError) -> AppBundleInfo
}
