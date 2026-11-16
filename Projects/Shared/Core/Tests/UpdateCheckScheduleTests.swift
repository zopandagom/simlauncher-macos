import Foundation
import Testing
@testable import Core

struct UpdateCheckScheduleTests {
  static let now = Date(timeIntervalSince1970: 1_800_000_000)

  @Test("isDue: 기록 없음·24시간 이상·미래 기록이면 참, 24시간 전이면 거짓")
  func isDue() {
    #expect(UpdateCheckSchedule.isDue(lastCheck: nil, now: Self.now))
    #expect(!UpdateCheckSchedule.isDue(lastCheck: Self.now.addingTimeInterval(-86399), now: Self.now))
    #expect(UpdateCheckSchedule.isDue(lastCheck: Self.now.addingTimeInterval(-86400), now: Self.now))
    #expect(UpdateCheckSchedule.isDue(lastCheck: Self.now.addingTimeInterval(1), now: Self.now))
    #expect(!UpdateCheckSchedule.isDue(lastCheck: Self.now, now: Self.now))
  }

  @Test("isRetryDue: 시작 없음·1시간 이상·미래면 참, 1시간 전이면 거짓")
  func isRetryDue() {
    #expect(UpdateCheckSchedule.isRetryDue(lastAttempt: nil, now: Self.now))
    #expect(!UpdateCheckSchedule.isRetryDue(lastAttempt: Self.now.addingTimeInterval(-3599), now: Self.now))
    #expect(UpdateCheckSchedule.isRetryDue(lastAttempt: Self.now.addingTimeInterval(-3600), now: Self.now))
    #expect(UpdateCheckSchedule.isRetryDue(lastAttempt: Self.now.addingTimeInterval(1), now: Self.now))
    #expect(!UpdateCheckSchedule.isRetryDue(lastAttempt: Self.now, now: Self.now))
  }

  @Test("간격 값: 24시간·1시간")
  func intervals() {
    #expect(UpdateCheckSchedule.interval == 86400)
    #expect(UpdateCheckSchedule.retryInterval == 3600)
  }
}
