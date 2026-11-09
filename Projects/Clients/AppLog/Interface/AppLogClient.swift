import Core

/// 앱을 로그 받기와 함께 실행하고, 기기·실행별 세션 버퍼와 끝남 이유를 갖는 Client (iOS·Android 공용).
/// 앱 출력은 화면에만 보인다: 파일·`Logger` 로 남기지 않고, SimLauncher 가 끝나면 사라진다.
public protocol AppLogClient: Sendable {
  /// iOS: 켜진 기기에서 설치된 앱을 로그 받기와 함께 실행하고(`SimulatorClient.launchWithConsole`), 실행 신호를 받거나 실패할 때까지
  /// 기다린다. 받기는 Client 가 소유한 작업에서 앱이 끝날 때까지 이어진다 (호출한 Task 의 취소는 받지 않는다).
  /// 같은 기기·같은 앱의 앞 세션은 이 실행이 대체한다 (끝나면 `.replaced`).
  /// 실행 신호 없이 simctl 이 0 으로 끝나도 성공으로 보고 그 세션은 곧바로 끝난 상태로 보인다.
  /// 신호도 끝남도 없이 오래(기본 60초) 지나면 실행된 것으로 보고 성공을 돌려준다 (그 뒤의 실패는 끝남으로만 보인다).
  func launchIOSApp(
    _ bundleID: AppBundleID,
    appName: String,
    on device: VirtualDevice.ID,
    deviceName: String
  ) async throws(AppLogLaunchError) -> AppLogSessionID

  /// Android: 켜진 기기에서 설치된 앱을 끄고 새로 실행하며 그 앱 메인 프로세스의 logcat 을 받는다
  /// (`AndroidEmulatorClient.launchWithLogcat`). pid 를 얻거나(또는 pid 전에 끝나 한 번 읽거나) 실패할 때까지 기다린다.
  /// 그 밖은 `launchIOSApp` 과 같다 (대체·신호 대기 상한·호출 Task 취소 무시).
  func launchAndroidApp(
    _ package: AndroidPackageName,
    appName: String,
    on device: AndroidVirtualDevice.ID,
    deviceName: String
  ) async throws(AppLogLaunchError) -> AppLogSessionID

  /// 세션과 같은 기기·앱을 다시 실행한다 (iOS 는 그 기기가 켜져 있으면 Simulator 앱을 연 뒤(실패는 무시) `launchIOSApp` 과 같다.
  /// Android 는 기기를 확인하지 않고 `launchAndroidApp` 과 같다 (꺼져 있으면 `.deviceNotBooted`)).
  /// 기기를 켜지 않는다 (꺼져 있으면 `.deviceNotBooted`). 세션이 없으면 `.sessionNotFound`.
  func relaunch(_ session: AppLogSessionID) async throws(AppLogLaunchError) -> AppLogSessionID

  /// SimLauncher 가 곧 이 기기의 이 앱을 다시 설치한다 (설치가 실행 중인 앱을 끝낸다, 측정): 받는 중인 그 앱의 세션이 끝나면 `.replaced`.
  func replacementWillStart(_ bundleID: AppBundleID, on device: VirtualDevice.ID) async
  /// 설치가 실패해 다시 실행하지 않는다: `replacementWillStart` 를 되돌린다.
  func replacementCancelled(_ bundleID: AppBundleID, on device: VirtualDevice.ID) async
  /// Android: SimLauncher 가 곧 이 기기의 이 패키지를 다시 설치한다 (iOS 와 같다).
  func replacementWillStart(_ package: AndroidPackageName, on device: AndroidVirtualDevice.ID) async
  /// Android: `replacementWillStart` 를 되돌린다.
  func replacementCancelled(_ package: AndroidPackageName, on device: AndroidVirtualDevice.ID) async

  /// 모든 세션 요약. 첫 알림은 지금 목록, 그 뒤는 세션이 생기거나 상태가 바뀌거나 정리될 때마다 (줄마다가 아니다). 시작 순.
  func sessionUpdates() async -> AsyncStream<[AppLogSessionSummary]>
  /// 세션의 줄. 첫 알림은 스냅숏, 그 뒤는 묶음(최대 약 100ms 마다). 세션이 정리되면 끝난다. 없는 세션이면 곧바로 끝난다.
  func lineUpdates(of session: AppLogSessionID) async -> AsyncStream<AppLogLineUpdate>

  /// 앱 종료 때: 모든 받기 작업을 기다리지 않고 취소한다(→ SIGINT. iOS 는 앱도 꺼지고 Android 는 앱이 남는다 — 기기 안 logcat 은
  /// 끝난다, 실측). 그 뒤 실행 요청은 `.commandFailed`.
  /// 메인에서 동기로 부를 수 있다.
  func stopAll()
}
