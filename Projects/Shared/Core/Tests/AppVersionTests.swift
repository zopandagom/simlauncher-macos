import Testing
@testable import Core

struct AppVersionTests {
  struct Accepted: Sendable, CustomTestStringConvertible {
    let raw: String
    let components: [Int]

    var testDescription: String {
      self.raw.debugDescription
    }
  }

  @Test(
    "받는 형식: 앞의 v·V 하나, 1~4 자리, 앞자리 0 은 값으로 읽고 끝의 0 은 뺀다",
    arguments: [
      Accepted(raw: "1.2.0", components: [1, 2]),
      Accepted(raw: "v1.2.0", components: [1, 2]),
      Accepted(raw: "V1.2", components: [1, 2]),
      Accepted(raw: "1", components: [1]),
      Accepted(raw: "1.2.3.4", components: [1, 2, 3, 4]),
      Accepted(raw: "01.2.0", components: [1, 2]),
      Accepted(raw: "0", components: [0]),
      Accepted(raw: "0.0.0", components: [0]),
      Accepted(raw: "123456789.0", components: [123_456_789]),
    ]
  )
  func accepts(_ accepted: Accepted) throws {
    let version = try #require(AppVersion(accepted.raw))
    #expect(version.components == accepted.components)
  }

  @Test(
    "거절: 빈 값·공백·접미사·태그 이름·빈 자리·5자리 이상·v 두 개·부호·전각 숫자·10자리 숫자",
    arguments: [
      "", " 1.2.0", "1.2.0 ", "1.2.0-beta", "1.2.0+3", "sample-catalog", "sample-catalog-v2", "1..2", ".1", "1.",
      "1.2.3.4.5", "vv1.0", "-1", "１.２", "1234567890", "v", "1.2.x",
    ]
  )
  func rejects(_ raw: String) {
    #expect(AppVersion(raw) == nil)
  }

  @Test("비교: 자리별 숫자, 짧은 쪽은 0 으로 채운다")
  func compares() throws {
    func version(_ raw: String) throws -> AppVersion {
      try #require(AppVersion(raw))
    }
    #expect(try version("1.2.0") < version("1.10.0"))
    #expect(try version("1.2") == version("1.2.0"))
    #expect(try version("1.2.0") < version("1.2.1"))
    #expect(try version("2.0") > version("1.99.99"))
    #expect(try version("1.2.0.1") > version("1.2.0"))
    #expect(try !(version("1.2.0") < version("1.2")))
    #expect(try Set([version("1.2"), version("v1.2.0")]).count == 1)
  }

  @Test("description: 3자리 미만은 0 을 채워 3자리, 4자리는 그대로, v 는 빠진다")
  func describes() throws {
    #expect(try #require(AppVersion("1.2")).description == "1.2.0")
    #expect(try #require(AppVersion("1")).description == "1.0.0")
    #expect(try #require(AppVersion("1.2.3.4")).description == "1.2.3.4")
    #expect(try #require(AppVersion("v1.3.0")).description == "1.3.0")
    #expect(try #require(AppVersion("1.2.3.0")).description == "1.2.3")
  }

  @Test("지난 git 태그 8개: 앱 태그 셋만 버전이고 샘플 태그는 비교 불가")
  func pastTags() {
    let parsed = [
      "sample-build-40048797216", "sample-build-40049792367", "sample-catalog", "1.0.0", "sample-build-40996774642",
      "sample-catalog-v2", "1.1.0", "1.2.0",
    ].map { AppVersion($0)?.description }
    #expect(parsed == [nil, nil, nil, "1.0.0", nil, nil, "1.1.0", "1.2.0"])
  }
}
