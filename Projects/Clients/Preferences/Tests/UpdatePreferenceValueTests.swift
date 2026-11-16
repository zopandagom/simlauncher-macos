import Core
import Foundation
import Testing
@testable import PreferencesImpl

struct UpdatePreferenceValueTests {
  struct BoolCase: Sendable, CustomTestStringConvertible {
    let value: StoredPlistValue?
    let expected: Bool

    var testDescription: String {
      String(describing: self.value)
    }
  }

  static let date = Date(timeIntervalSince1970: 1_800_000_000)

  @Test(
    "AutomaticUpdateCheck 읽기: 키 없음 켬, Bool·숫자 0·1·문자열 yes/true/1/no/false/0, 그 밖은 끔",
    arguments: [
      BoolCase(value: nil, expected: true),
      BoolCase(value: .bool(true), expected: true),
      BoolCase(value: .bool(false), expected: false),
      BoolCase(value: .integer(1), expected: true),
      BoolCase(value: .integer(0), expected: false),
      BoolCase(value: .integer(2), expected: false),
      BoolCase(value: .string("YES"), expected: true),
      BoolCase(value: .string("no"), expected: false),
      BoolCase(value: .string("True"), expected: true),
      BoolCase(value: .string("0"), expected: false),
      BoolCase(value: .string("1"), expected: true),
      BoolCase(value: .string("maybe"), expected: false),
      BoolCase(value: .string(""), expected: false),
      BoolCase(value: .array(["YES"]), expected: false),
      BoolCase(value: .date(Date(timeIntervalSince1970: 0)), expected: false),
    ]
  )
  func automaticUpdateCheck(_ testCase: BoolCase) {
    #expect(UpdatePreferenceValue.automaticUpdateCheck(from: testCase.value?.any) == testCase.expected)
  }

  @Test("문자열 읽기: 문자열만, 그 밖은 nil")
  func string() {
    #expect(UpdatePreferenceValue.string(from: "1.3.0") == "1.3.0")
    #expect(UpdatePreferenceValue.string(from: nil) == nil)
    #expect(UpdatePreferenceValue.string(from: NSNumber(value: 1)) == nil)
    #expect(UpdatePreferenceValue.string(from: ["1.3.0"]) == nil)
  }

  @Test("날짜 읽기: 날짜만, 그 밖은 nil")
  func date() {
    #expect(UpdatePreferenceValue.date(from: Self.date) == Self.date)
    #expect(UpdatePreferenceValue.date(from: nil) == nil)
    #expect(UpdatePreferenceValue.date(from: "2026-11-15") == nil)
    #expect(UpdatePreferenceValue.date(from: NSNumber(value: 1_800_000_000)) == nil)
  }

  @Test("숨김 사전 읽기: 정상이면 값, version·dismissedAt 이 빠지거나 타입이 다르거나 해석 불가면 nil")
  func bannerDismissal() throws {
    let expected = try UpdateBannerDismissal(version: #require(AppVersion("1.3.0")), dismissedAt: Self.date)
    #expect(UpdatePreferenceValue.bannerDismissal(from: ["version": "1.3.0", "dismissedAt": Self.date]) == expected)
    #expect(UpdatePreferenceValue.bannerDismissal(from: ["version": "v1.3", "dismissedAt": Self.date]) == expected)

    let rejected: [Any?] = [
      nil,
      "1.3.0",
      ["1.3.0"],
      ["dismissedAt": Self.date],
      ["version": NSNumber(value: 1), "dismissedAt": Self.date],
      ["version": "abc", "dismissedAt": Self.date],
      ["version": "1.3.0"],
      ["version": "1.3.0", "dismissedAt": "2026-11-15"],
    ]
    for value in rejected {
      #expect(UpdatePreferenceValue.bannerDismissal(from: value) == nil)
    }
  }

  @Test("plist(for:) 로 쓴 값을 다시 읽으면 같은 숨김")
  func roundTrip() throws {
    let dismissal = try UpdateBannerDismissal(version: #require(AppVersion("1.2")), dismissedAt: Self.date)
    let plist = UpdatePreferenceValue.plist(for: dismissal)
    #expect(plist["version"] as? String == "1.2.0")
    #expect(plist["dismissedAt"] as? Date == Self.date)
    #expect(UpdatePreferenceValue.bannerDismissal(from: plist) == dismissal)
  }
}
