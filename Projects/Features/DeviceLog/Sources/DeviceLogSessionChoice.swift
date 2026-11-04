import AppLogInterface
import Core

/// 창이 보일 세션을 고르는 규칙 (순수). 세션 목록은 시작 시각 순이다 (`AppLogClient.sessionUpdates`).
enum DeviceLogSessionChoice {
  /// 대상의 세션 (시작 시각 순).
  static func sessions(of target: AppLogTarget, in sessions: [AppLogSessionSummary]) -> [AppLogSessionSummary] {
    sessions.filter { $0.target == target }
  }

  /// 대상의 가장 늦게 시작한 세션. 창을 열 때 고른다.
  static func latest(of target: AppLogTarget, in sessions: [AppLogSessionSummary]) -> AppLogSessionID? {
    sessions.last { $0.target == target }?.id
  }

  /// 세션 목록이 바뀐 뒤 열린 창이 보일 세션.
  /// - 고른 세션이 없거나 목록에서 사라졌으면 대상의 가장 늦은 세션 (없으면 nil, 빈 화면).
  /// - 고른 세션과 같은 앱(같은 대상·같은 앱 ID)의 더 늦은 세션이 생겼으면 그 가장 늦은 것 (다시 설치·다시 실행).
  ///   다른 앱의 새 세션으로는 옮기지 않는다.
  static func selection(
    current: AppLogSessionID?, of target: AppLogTarget, in sessions: [AppLogSessionSummary]
  ) -> AppLogSessionID? {
    guard let current, let selected = sessions.first(where: { $0.id == current }) else {
      return self.latest(of: target, in: sessions)
    }
    let sameApp = sessions.last { $0.target == target && $0.appID == selected.appID }
    return sameApp?.id ?? current
  }
}
