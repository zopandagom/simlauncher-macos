import Core

/// iOS 기기 목록이 기기 수명(끄기 전후·목록 읽기)을 App 에 알리는 클로저 묶음. App 이 레이아웃 러너 정리에 잇는다.
/// `simulator` 처럼 `LauncherModel` 이 생성 때 받는 의존이고(Model 상태를 바꾸는 창구가 아니다), Feature 는 받는 쪽을 모른다.
/// - `willShutDown`: "끄기" 가 `simctl shutdown` 을 부르기 직전. 끝날 때까지 기다린 뒤 끈다 (꺼진 기기에서는 앱을 지울 수 없어서).
/// - `didShutDown`: 끄기가 끝난 뒤 (성공·실패 모두). `willShutDown` 과 같은 ID 로 한 번.
/// - `listed`: iOS 기기 목록을 읽을 때마다 켜진 기기 ID 집합으로 (꺼진·켜는 중 기기는 빠진다). 실패한 읽기에서는 부르지 않는다.
///   동기이고 기다리지 않는다 (목록 갱신이 느려지지 않게. 받는 쪽이 할 일을 따로 시작한다).
public struct LauncherDeviceHooks: Sendable {
  public let willShutDown: @Sendable (VirtualDevice.ID) async -> Void
  public let didShutDown: @Sendable (VirtualDevice.ID) async -> Void
  public let listed: @Sendable (Set<VirtualDevice.ID>) -> Void

  public init(
    willShutDown: @escaping @Sendable (VirtualDevice.ID) async -> Void,
    didShutDown: @escaping @Sendable (VirtualDevice.ID) async -> Void,
    listed: @escaping @Sendable (Set<VirtualDevice.ID>) -> Void
  ) {
    self.willShutDown = willShutDown
    self.didShutDown = didShutDown
    self.listed = listed
  }

  /// 셋 다 아무것도 하지 않는다 (기본값: 테스트·Example).
  public static let none = LauncherDeviceHooks(willShutDown: { _ in }, didShutDown: { _ in }, listed: { _ in })
}
