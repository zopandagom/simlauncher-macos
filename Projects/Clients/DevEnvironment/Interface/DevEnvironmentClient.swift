import Core

/// 쓸 Xcode 를 고르고 준비 상태를 확인하는 Client. 고르는 규칙은 `XcodeSelection.choose` 하나다:
/// xcode-select 가 가리키는 Xcode → 없으면 /Applications 의 가장 높은 버전.
/// Xcode 를 찾지 못하면 xcodebuild 를 실행하지 않는다. `/usr/bin/xcodebuild` shim 으로 넘어가지 않는다
/// (개발자 도구가 없는 Mac 에서 Command Line Tools 설치 대화상자를 띄울 수 있다).
public protocol DevEnvironmentClient: Sendable {
  /// 지금 쓸 Xcode. 없으면 nil. 실행하는 명령은 `xcode-select -p` 하나뿐이고, 실패해도 /Applications 로 계속 찾는다.
  /// 부를 때마다 다시 찾는다 (앱을 켜 둔 채 Xcode 를 설치·삭제해도 다음 호출에 반영).
  /// App 은 이것을 다른 Client 의 개발자 디렉터리 provider 로 넘긴다.
  func selectedXcode() async -> XcodeInstallation?

  /// 쓸 Xcode 와 준비 상태. Xcode 가 있으면 그 안의 xcodebuild 로 `-checkFirstLaunchStatus`,
  /// 0 이 아니면 `-license check` 를 더 실행한다. xcodebuild 를 시작하지 못하면 `.checkFailed`.
  func checkEnvironment() async throws(DevEnvironmentError) -> DevEnvironmentStatus

  /// 지금 쓸 Xcode 를 연다 (라이선스 동의·추가 구성요소 설치 창이 Xcode 에서 뜬다, 관리자 암호 필요).
  /// 부를 때 다시 고르고, 없으면 실행하지 않고 `.xcodeNotFound`.
  func openXcode() async throws(DevEnvironmentError)

  /// App Store 앱의 Xcode 페이지를 연다.
  func openXcodeInAppStore() async throws(DevEnvironmentError)
}
