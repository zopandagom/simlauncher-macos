import Foundation
import Testing
@testable import Core

struct UpdateBannerDismissalTests {
  static let dismissedAt = Date(timeIntervalSince1970: 1_800_000_000)

  static func version(_ raw: String) throws -> AppVersion {
    try #require(AppVersion(raw))
  }

  @Test("같은 버전은 0초·86,399초 뒤 가리고 86,400초 뒤 가리지 않는다")
  func hidesForADay() throws {
    let dismissal = try UpdateBannerDismissal(version: Self.version("1.3.0"), dismissedAt: Self.dismissedAt)
    let version = try Self.version("1.3.0")
    #expect(dismissal.hides(version, now: Self.dismissedAt))
    #expect(dismissal.hides(version, now: Self.dismissedAt.addingTimeInterval(86399)))
    #expect(!dismissal.hides(version, now: Self.dismissedAt.addingTimeInterval(86400)))
  }

  @Test("다른(더 새) 버전은 가리지 않는다")
  func otherVersion() throws {
    let dismissal = try UpdateBannerDismissal(version: Self.version("1.3.0"), dismissedAt: Self.dismissedAt)
    #expect(try !dismissal.hides(Self.version("1.4.0"), now: Self.dismissedAt.addingTimeInterval(60)))
  }

  @Test("숨긴 시각이 미래(시계가 뒤로 감)면 가리지 않는다")
  func futureDismissal() throws {
    let dismissal = try UpdateBannerDismissal(version: Self.version("1.3.0"), dismissedAt: Self.dismissedAt)
    #expect(try !dismissal.hides(Self.version("1.3.0"), now: Self.dismissedAt.addingTimeInterval(-1)))
  }

  @Test("1.2 로 만든 숨김이 1.2.0 을 가린다 (정규화)")
  func normalized() throws {
    let dismissal = try UpdateBannerDismissal(version: Self.version("1.2"), dismissedAt: Self.dismissedAt)
    #expect(try dismissal.hides(Self.version("1.2.0"), now: Self.dismissedAt.addingTimeInterval(10)))
  }
}
