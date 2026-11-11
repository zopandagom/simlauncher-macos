import Core

/// 켜진 기기 화면의 뷰 계층과 스크린샷을 한 번에 읽는다 (레이아웃 창). 결과는 메모리에만 둔다.
/// Android 는 AndroidEmulator Client 의 `layoutSnapshot` 을 조합한다. iOS 는 SimLauncher 가 빌드해 띄운 XCUITest 러너로 읽는다.
public protocol ScreenLayoutClient: Sendable {
  /// 대상 기기의 레이아웃 스냅샷. 호출한 Task 가 취소되면 `.cancelled`.
  /// `onPhase` 는 단계가 바뀔 때마다(돌아오기 전에만) 부른다. Android 는 `.reading` 한 번. iOS 는 러너를 새로 띄워야 할 때
  /// (첫 사용, 러너가 멈춘 뒤 — 10분 유휴·기기 끄기나 다시 켜기·요청 시간 초과·러너 종료 — , Xcode 교체 뒤)
  /// `.preparing` 뒤 `.reading`, 아니면 `.reading` 한 번.
  func snapshot(
    of target: LayoutTarget,
    onPhase: @escaping @Sendable (LayoutReadPhase) async -> Void
  ) async throws(ScreenLayoutError) -> LayoutSnapshot

  /// 창 제목에 쓸 기기 이름 (첫 스냅샷 전, iOS 는 러너 준비로 수 초~2분이 걸린다). 모르면(목록을 읽지 못함·기기 없음) nil.
  /// iOS 는 시뮬레이터 기기 목록의 이름. Android 는 nil (목록 읽기가 무겁고, 스냅샷이 약 2초 안에 이름을 가져온다).
  func deviceName(of target: LayoutTarget) async -> String?
}

/// 레이아웃 읽기의 단계.
public enum LayoutReadPhase: Hashable, Sendable {
  /// 읽을 준비를 한다 (iOS: 러너 빌드·설치·실행, 수 초~2분). Android 는 보내지 않는다.
  case preparing
  /// 화면을 읽는다.
  case reading
}

/// 레이아웃 읽기 실패. 화면 문구는 Feature 가 정한다.
public enum ScreenLayoutError: Error, Hashable, Sendable {
  // MARK: iOS 전용 (iOS 경로가 만든다)

  /// 쓸 Xcode 가 없거나 준비되지 않았다.
  case xcodeUnavailable
  /// 레이아웃을 읽을 준비(러너 빌드·설치·실행)를 하지 못했다.
  case inspectorSetupFailed
  /// 읽는 동안 앞 앱이 사라졌다 (앞 앱이 없으면 홈 화면 같은 시스템 화면을 읽는다).
  case appNotInForeground

  // MARK: 공용

  case deviceNotFound
  /// 쓸 수 없는 기기 (이유는 기기 목록 행이 보인다).
  case deviceUnavailable
  /// 켜져 있지 않다 (꺼짐·켜는 중, 읽는 중 끊김).
  case deviceNotBooted
  /// 기기 도구(Android SDK·adb)를 쓸 수 없거나 adb 가 답하지 않는다.
  case toolsUnavailable
  /// 화면이 계속 바뀌어(애니메이션·동영상) 읽지 못했다.
  case screenNotIdle
  /// 기기 화면이 꺼져 있다.
  case displayOff
  /// 다른 자동화 도구가 같은 기기의 화면 정보를 읽고 있다.
  case automationBusy
  /// 기기가 시간 안에 답하지 않았다.
  case timedOut
  /// 화면 정보·스크린샷을 해석하지 못했다.
  case unreadable
  case cancelled
  /// 이 빌드가 읽지 못하는 플랫폼. 지금은 만들지 않는다 (남겨 둔 case).
  case unsupportedPlatform
}
