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

  /// 세션 목록이 바뀐 뒤 열린 창이 보일 세션. `previous` 는 이번 목록을 받기 전 Model 이 갖고 있던 세션 id 들이다.
  /// "새로 생긴" 세션은 `previous` 에 없던 세션이다.
  /// 1. 고른 세션이 없으면 대상의 가장 늦은 세션 (없으면 nil, 빈 화면).
  /// 2. 고른 세션이 새 목록에 없을 때: 앞 목록에 있었으면(정리·제거로 빠짐) 대상의 가장 늦은 세션 (없으면 nil),
  ///    앞 목록에도 없었으면(다시 실행 결과가 그 세션이 든 알림보다 먼저 옴) 그대로.
  /// 3. 고른 세션이 새 목록에 있을 때: 같은 앱(같은 대상·같은 앱 ID)의 새로 생긴 세션이 있으면 그 가장 늦은 것
  ///    (다시 설치·다시 실행), 없으면 그대로. 다른 앱의 새 세션·상태 바뀜·다른 기기 알림으로는 옮기지 않아,
  ///    사용자가 앞 실행을 고른 뒤 다른 알림이 와도 그 실행에 남는다.
  static func selection(
    current: AppLogSessionID?,
    of target: AppLogTarget,
    previous: Set<AppLogSessionID>,
    in sessions: [AppLogSessionSummary]
  ) -> AppLogSessionID? {
    guard let current else { return self.latest(of: target, in: sessions) }
    guard let selected = sessions.first(where: { $0.id == current }) else {
      return previous.contains(current) ? self.latest(of: target, in: sessions) : current
    }
    let newSameApp = sessions.last {
      $0.target == target && $0.appID == selected.appID && !previous.contains($0.id)
    }
    return newSameApp?.id ?? current
  }
}
