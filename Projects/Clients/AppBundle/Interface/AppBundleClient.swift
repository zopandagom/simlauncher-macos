import Core
import Foundation

/// 로컬 iOS 앱 번들(.app)을 읽는 Client. .app 을 읽고, zip 은 임시 폴더에 풀어 검사한다. 원본 파일은 고치지 않는다.
public protocol AppBundleClient: Sendable {
  /// 이 Mac 의 iOS 시뮬레이터가 실행하는 아키텍처. Apple 실리콘이면 arm64 (Rosetta 로 실행 중이어도), 아니면 x86_64.
  var hostArchitecture: CPUArchitecture { get }

  /// .app 의 Info.plist 와 실행 파일 헤더를 읽는다. 설치 가능 판정은 하지 않는다 (Core `installProblem`).
  /// 심볼릭 링크를 푼 실제 경로로 검사하고, 그 경로를 결과의 `location` 에 담는다.
  func inspect(_ url: URL) async throws(AppBundleError) -> AppBundleInfo

  /// zip 맨 위의 .app 하나를 새 임시 폴더에 풀고 검사한다 (설치 판정은 하지 않는다).
  /// 실패하면 만든 폴더를 지우고 던진다. 성공하면 호출한 쪽이 `removeExtracted(_:)` 를 부른다.
  func extractApp(fromZip url: URL) async throws(AppBundleError) -> ExtractedApp

  /// `extractApp(fromZip:)` 이 만든 폴더를 지운다. 실패는 던지지 않는다 (다음에 기기 목록 화면을 열 때 다시 지운다).
  /// 이 Client 가 만든 형식의 폴더가 아니면 아무것도 하지 않는다.
  func removeExtracted(_ extracted: ExtractedApp) async

  /// 남은 `SimLauncher-Unzip-*` 폴더(앞선 실행이 남겼거나 이 프로세스에서 지우지 못한 것)를 지운다. 이 프로세스가 지금 쓰는 폴더는 건너뛴다. 실패는 무시한다.
  func removeLeftoverExtractions() async
}
