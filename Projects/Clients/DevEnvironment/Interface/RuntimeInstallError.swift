/// 런타임 설치 실패. 화면 문구는 Feature 가 정하고 명령 원문은 담지 않는다.
/// `DevEnvironmentError` 와 따로 둔다 (환경 확인 화면의 분기에 설치 실패가 섞이지 않게).
public enum RuntimeInstallError: Error, Hashable, Sendable {
  /// 쓸 Xcode 가 없어 실행하지 않았다.
  case xcodeNotFound
  /// 고른 Xcode 의 xcodebuild 를 시작하지 못했다.
  case launchFailed
  /// Task 취소로 멈췄다. 돌아올 때 xcodebuild 는 끝나 있다 (내려받기 중 SIGINT 는 exit 70, 설치되지 않음).
  case cancelled
  /// 그 밖의 0 이 아닌 종료, 또는 xcodebuild 가 내려받기를 취소했다고 알림. 네트워크·디스크 원인은 구분하지 않는다
  /// (약 1.5분 끊김은 실패하지 않고 기다렸고, 더 긴 끊김·디스크 부족의 문구는 미확인).
  case failed
}
