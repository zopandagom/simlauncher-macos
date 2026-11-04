/// `launchWithConsole` 이 넘기는 알림.
public enum AppConsoleEvent: Hashable, Sendable {
  /// 앱이 실행됐다 (simctl 의 실행 신호 줄 또는 앱의 첫 줄 중 먼저 온 것). 실행마다 한 번.
  case launched
  /// 앱 출력 줄, 받은 순서대로 (줄 끝 문자는 뺐다). stdout·stderr·NSLog·Logger 를 구별하지 않는다.
  case lines([String])
}

/// `launchWithConsole` 의 끝.
public enum AppConsoleEnd: Hashable, Sendable {
  /// simctl 이 스스로 끝났다: 앱이 끝났거나(종료·크래시·다른 실행이 대체·다시 설치) 기기가 꺼졌다. 종료 코드로 원인을 가르지 못한다.
  case exited
  /// 호출한 Task 가 취소되어 멈췄다 (앱도 끝난다). 실행 신호 전이면 `.launched` 를 부르지 않았다.
  case stopped
}
