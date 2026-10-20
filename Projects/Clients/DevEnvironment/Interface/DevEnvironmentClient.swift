import Core

/// 쓸 Xcode 를 고르고 준비 상태를 확인하고, 그 Xcode 의 기본 iOS 런타임을 설치하는 Client. 고르는 규칙은 `XcodeSelection.choose` 하나다:
/// xcode-select 가 가리키는 Xcode → 없으면 /Applications 의 가장 높은 버전.
/// Xcode 를 찾지 못하면 xcodebuild 를 실행하지 않는다. `/usr/bin/xcodebuild` shim 으로 넘어가지 않는다
/// (개발자 도구가 없는 Mac 에서 Command Line Tools 설치 대화상자를 띄울 수 있다).
public protocol DevEnvironmentClient: Sendable {
  /// 지금 쓸 Xcode. 없으면 nil. 실행하는 명령은 `xcode-select -p` 하나뿐이고, 실패하거나 30초 안에 끝나지 않아도
  /// /Applications 로 계속 찾는다. xcode-select 는 호출한 Task 의 취소를 받지 않는다 (취소돼도 고른 Xcode 가 바뀌지 않는다).
  /// 부를 때마다 다시 찾는다 (앱을 켜 둔 채 Xcode 를 설치·삭제해도 다음 호출에 반영).
  /// App 은 이것을 다른 Client 의 개발자 디렉터리 provider 로 넘긴다.
  func selectedXcode() async -> XcodeInstallation?

  /// 쓸 Xcode 와 준비 상태. Xcode 가 있으면 그 안의 xcodebuild 로 `-checkFirstLaunchStatus`,
  /// 0 이 아니면 `-license check` 를 더 실행한다. 확인 명령은 각각 30초가 지나면 멈추기 시작한다.
  /// xcodebuild 를 시작하지 못했거나 시간 초과·취소로 멈췄으면 `.checkFailed`.
  func checkEnvironment() async throws(DevEnvironmentError) -> DevEnvironmentStatus

  /// 지금 쓸 Xcode 를 연다 (라이선스 동의·추가 구성요소 설치 창이 Xcode 에서 뜬다, 관리자 암호 필요).
  /// 부를 때 다시 고르고, 없으면 실행하지 않고 `.xcodeNotFound`.
  func openXcode() async throws(DevEnvironmentError)

  /// App Store 앱의 Xcode 페이지를 연다.
  func openXcodeInAppStore() async throws(DevEnvironmentError)

  /// 지금 쓸 Xcode 의 기본 iOS 런타임 (iOS Simulator SDK 의 버전·build). Xcode 가 없거나 SDK 파일을 못 읽으면 nil.
  /// 실행하는 명령은 쓸 Xcode 를 고르는 `xcode-select -p` 하나뿐이고 네트워크를 쓰지 않는다.
  func defaultIOSRuntime() async -> DefaultIOSRuntime?

  /// 지금 쓸 Xcode 의 기본 iOS 런타임을 Apple 서버에서 내려받아 설치한다 (`xcodebuild -downloadPlatform iOS`, 버전 지정 없음).
  /// 부를 때 Xcode 를 다시 고르고, 없으면 실행하지 않고 `.xcodeNotFound`. 진행은 `progress` 로 순서대로 알린다
  /// (첫 알림은 `.preparing`, 앞 알림이 끝난 뒤 다음, 돌아오기 전에 모든 알림이 끝난다).
  /// Task 가 취소되면 xcodebuild 를 멈추고 끝난 뒤 `.cancelled`. 돌아오면 xcodebuild 는 끝나 있다.
  /// 예외: xcodebuild 가 스스로 끝난 뒤(멈추기 전에) 온 취소면 결과(`.installed`·`.alreadyInstalled` 또는 `.failed`)를
  /// 돌려줄 수 있다.
  /// 시간 제한은 없다 (네트워크가 끊겨도 xcodebuild 는 실패하지 않고 기다린다. 멈춤 안내는 화면이 진행 변화로 정한다).
  /// 동시에 부르면 각각 실행한다 (막는 것은 호출하는 쪽).
  /// 끝나도 런타임이 바로 Ready 가 아닐 수 있다: 호출한 쪽이 결과와 관계없이 `SimulatorClient.fetchRuntimeImages()` 로 다시 본다.
  func installDefaultIOSRuntime(
    progress: @escaping @Sendable (RuntimeInstallProgress) async -> Void
  ) async throws(RuntimeInstallError) -> RuntimeInstallOutcome
}
