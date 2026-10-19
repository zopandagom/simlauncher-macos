import Testing
@testable import Core

struct DeviceRuntimeTests {
  @Test(
    "OS 버전 문자열을 해석한다",
    arguments: [
      ("27.0", OSVersion(major: 27)),
      ("26.0.1", OSVersion(major: 26, minor: 0, patch: 1)),
      ("18", OSVersion(major: 18)),
      ("17.4", OSVersion(major: 17, minor: 4)),
    ]
  )
  func parsesVersion(string: String, expected: OSVersion) {
    #expect(OSVersion(string) == expected)
  }

  @Test("숫자 1~3 개가 아니면 OS 버전이 아니다", arguments: ["", "a", "27.x", "27..0", "1.2.3.4", "-1", "27.0 ", "２７"])
  func rejectsInvalidVersion(string: String) {
    #expect(OSVersion(string) == nil)
  }

  @Test("OS 버전은 major·minor·patch 순서로 비교한다")
  func comparesVersions() {
    #expect(OSVersion(major: 26, minor: 9) < OSVersion(major: 27))
    #expect(OSVersion(major: 27, minor: 0, patch: 1) > OSVersion(major: 27))
    #expect(OSVersion(major: 27, minor: 1) > OSVersion(major: 27, minor: 0, patch: 9))
    #expect(OSVersion(major: 17, minor: 10) > OSVersion(major: 17, minor: 9))
  }

  @Test(
    "OS 버전 문자열 표기는 major.minor 이고, patch 가 있으면 붙인다",
    arguments: [
      (OSVersion(major: 27), "27.0"),
      (OSVersion(major: 27, minor: 1), "27.1"),
      (OSVersion(major: 26, minor: 0, patch: 1), "26.0.1"),
    ]
  )
  func describesVersion(version: OSVersion, expected: String) {
    #expect(version.description == expected)
    #expect(expected == "\(version)")
  }

  @Test(
    "simctl 플랫폼 이름을 플랫폼으로 바꾸고, 모르는 이름은 other",
    arguments: [
      ("iOS", DevicePlatform.iOS),
      ("watchOS", .watchOS),
      ("tvOS", .tvOS),
      ("xrOS", .visionOS),
      ("visionOS", .visionOS),
      ("ios", .other),
      ("macOS", .other),
      ("", .other),
    ]
  )
  func mapsPlatform(raw: String, expected: DevicePlatform) {
    #expect(DevicePlatform(simctlPlatform: raw) == expected)
  }
}
