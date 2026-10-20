/// 환경 확인·열기 실패. 화면 문구는 Feature 가 정하고 명령 원문은 담지 않는다.
public enum DevEnvironmentError: Error, Hashable, Sendable {
  /// 쓸 Xcode 가 없어 열지 않았다 (`openXcode`).
  case xcodeNotFound
  /// 고른 Xcode 의 xcodebuild 를 시작하지 못했다 (설치 중·손상, `checkEnvironment`).
  case checkFailed
  /// `open` 을 시작하지 못했거나 0 이 아닌 종료 코드 (`openXcode`·`openXcodeInAppStore`).
  case openFailed
}
