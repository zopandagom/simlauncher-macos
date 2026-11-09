import Core

/// 로그 받기와 함께 하는 앱 실행의 실패. 화면 문구는 Feature 가 케이스별로 정한다.
/// iOS 는 Simulator 의 실행 실패(`SimulatorError`)와 같은 이름끼리 1:1 이다 (Interface 는 다른 Client Interface 에 의존하지 않아 따로 둔다).
/// Android 는 `AndroidEmulatorError` 의 흔한 실행 실패를 같은 뜻의 케이스로 옮기고(이름이 다른 것: `sdkUnavailable` →
/// `developerToolsUnavailable`, `launchFailed(.notInstalled)` → `appNotInstalled`, `launchFailed(.noLauncherActivity)`
/// →
/// `noLauncherActivity`), 그 밖(`appCommandFailed`·드문 사전 확인 실패)은 `commandFailed` 로 모은다.
public enum AppLogLaunchError: Error, Hashable, Sendable {
  /// iOS: 쓸 Xcode 가 없거나 simctl 을 띄우지 못했다. Android: Android 도구(SDK)를 쓸 수 없다.
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
  /// Android: 기기를 쓸 수 없다 (이유는 기기 목록과 같다).
  case deviceUnavailable(AndroidVirtualDevice.UnavailableReason)
  /// Android: 설치되어 있지만 홈 화면에서 여는 화면(launcher activity)이 없다.
  case noLauncherActivity
  /// Android: 기기 상태를 adb 로 확인하지 못했다 (adb 가 답하지 않음·시작 실패).
  case adbUnavailable
}
