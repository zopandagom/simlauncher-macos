import Foundation

/// 업데이트 자동 확인의 시간 규칙. 서버가 답한 확인은 기록(`LastUpdateCheck`) 기준 24시간, 서버에 닿지 못한 실패는
/// 이 실행의 마지막 요청 시작 기준 1시간 뒤에만 다시 자동으로 요청한다.
public enum UpdateCheckSchedule {
  /// 자동 확인 간격: 24시간. 기록(서버가 답한 확인) 기준.
  public static let interval: TimeInterval = 86400
  /// 서버에 닿지 못한 뒤 자동 재시도 간격: 1시간. 이 실행의 마지막 요청 시작 기준 (메모리).
  public static let retryInterval: TimeInterval = 3600

  /// 기록 기준으로 자동 확인할 때인가: 기록 없음 → true, 기록이 지금보다 미래(시계가 뒤로 감) → true, 지난 시간 ≥ interval → true, 아니면 false.
  public static func isDue(lastCheck: Date?, now: Date) -> Bool {
    self.hasElapsed(self.interval, since: lastCheck, now: now)
  }

  /// 이 실행의 마지막 요청 시작 기준으로 다시 요청해도 되는가: 없음 → true, 미래 → true, 지난 시간 ≥ retryInterval → true, 아니면 false.
  public static func isRetryDue(lastAttempt: Date?, now: Date) -> Bool {
    self.hasElapsed(self.retryInterval, since: lastAttempt, now: now)
  }

  private static func hasElapsed(_ duration: TimeInterval, since date: Date?, now: Date) -> Bool {
    guard let date else {
      return true
    }
    if date > now {
      return true
    }
    return now.timeIntervalSince(date) >= duration
  }
}
