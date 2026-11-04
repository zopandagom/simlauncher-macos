/// 로그 받기와 함께 하는 앱 실행의 실패. 화면 문구는 Feature 가 케이스별로 정한다.
/// iOS 는 Simulator 의 실행 실패(`SimulatorError`)와 같은 이름끼리 1:1 이다 (Interface 는 다른 Client Interface 에 의존하지 않아 따로 둔다).
public enum AppLogLaunchError: Error, Hashable, Sendable {
  /// 쓸 Xcode 가 없거나 simctl 을 띄우지 못했다.
  case developerToolsUnavailable
  /// 기기를 찾지 못했다.
  case deviceNotFound
  /// 기기가 켜져 있지 않다 (다시 실행은 기기를 켜지 않는다).
  case deviceNotBooted
  /// 그 앱이 기기에 없다.
  case appNotInstalled
  /// 실행을 요청했지만 앱이 시작되지 않았다.
  case appLaunchFailed
  /// 그 밖의 실패 (SimLauncher 가 끝나는 중의 실행 요청 포함).
  case commandFailed
  /// 다시 실행할 세션이 없다 (버퍼 정리로 사라짐).
  case sessionNotFound
}
