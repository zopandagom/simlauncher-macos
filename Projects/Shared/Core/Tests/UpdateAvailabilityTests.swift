import Testing
@testable import Core

struct UpdateAvailabilityTests {
  static func version(_ raw: String) throws -> AppVersion {
    try #require(AppVersion(raw))
  }

  @Test("지금 버전을 모르면 최신과 관계없이 currentUnknown")
  func currentUnknown() throws {
    let latest = try Self.version("1.3.0")
    #expect(UpdateAvailability.judge(current: nil, latest: latest, skipped: []) == .currentUnknown)
    #expect(UpdateAvailability.judge(current: nil, latest: nil, skipped: []) == .currentUnknown)
  }

  @Test("최신 버전 값을 모르면 latestUnrecognized")
  func latestUnrecognized() throws {
    let result = try UpdateAvailability.judge(current: Self.version("1.2.0"), latest: nil, skipped: [])
    #expect(result == .latestUnrecognized)
  }

  @Test("최신이 더 높으면 newer, 건너뛴 집합에 있으면 skipped 참, 다른 버전만 있으면 거짓")
  func newer() throws {
    let current = try Self.version("1.2.0")
    let latest = try Self.version("1.3.0")
    #expect(UpdateAvailability.judge(current: current, latest: latest, skipped: []) == .newer(latest, skipped: false))
    #expect(
      try UpdateAvailability.judge(current: current, latest: latest, skipped: [Self.version("1.3")])
        == .newer(latest, skipped: true)
    )
    #expect(
      try UpdateAvailability.judge(current: current, latest: latest, skipped: [Self.version("1.2.5")])
        == .newer(latest, skipped: false)
    )
  }

  @Test("같거나 지금이 더 높으면 upToDate")
  func upToDate() throws {
    let same = try UpdateAvailability.judge(current: Self.version("1.2.0"), latest: Self.version("1.2"), skipped: [])
    let older = try UpdateAvailability.judge(current: Self.version("1.3.0"), latest: Self.version("1.2.0"), skipped: [])
    #expect(same == .upToDate)
    #expect(older == .upToDate)
  }
}
