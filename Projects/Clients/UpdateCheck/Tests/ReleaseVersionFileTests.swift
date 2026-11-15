import Core
import Foundation
import Testing
import UpdateCheckInterface
@testable import UpdateCheckImpl

struct ReleaseVersionFileTests {
  @Test("릴리스 스크립트 출력과 같은 바이트 {\"version\":\"1.2.0\"} + 줄바꿈은 1.2.0")
  func parsesReleaseScriptOutput() throws {
    let data = Data("{\"version\":\"1.2.0\"}\n".utf8)
    #expect(data == versionFileJSON("1.2.0"))
    #expect(try ReleaseVersionFile.version(from: data) == version("1.2.0"))
  }

  @Test("모르는 키는 무시하고 version 만 읽는다")
  func ignoresUnknownKeys() throws {
    let body = #"{"version":"1.10.0","sha256":"x"}"#
    #expect(try ReleaseVersionFile.version(from: Data(body.utf8)) == version("1.10.0"))
  }

  @Test("공백·줄바꿈이 낀 JSON 도 읽는다")
  func acceptsWhitespace() throws {
    let body = "\n  {\n    \"version\" : \"1.3.0\"\n  }\n\n"
    #expect(try ReleaseVersionFile.version(from: Data(body.utf8)) == version("1.3.0"))
  }

  @Test("v1.3.0 은 AppVersion 규칙대로 1.3.0")
  func acceptsVPrefix() throws {
    #expect(try ReleaseVersionFile.version(from: versionFileJSON("v1.3.0")) == version("1.3.0"))
  }

  @Test("숫자 버전이 아닌 값은 nil (비교 불가)", arguments: ["sample-catalog", "", "1.2.0-beta"])
  func unrecognizedValue(_ raw: String) throws {
    #expect(try ReleaseVersionFile.version(from: versionFileJSON(raw)) == nil)
  }

  @Test(
    "JSON 객체가 아니거나 version 이 없거나 문자열이 아니면 unexpectedResponse (옛 API 모양 응답도 거절)",
    arguments: [
      "{}",
      #"{"version":null}"#,
      #"{"version":1.2}"#,
      #"{"version":["1.2.0"]}"#,
      #"["1.2.0"]"#,
      #""1.2.0""#,
      "1.2.0",
      "",
      "Not Found",
      "<html><body>blocked</body></html>",
      #"{"tag_name":"1.2.0"}"#,
    ]
  )
  func rejectsMalformed(_ body: String) {
    #expect(throws: UpdateCheckError.unexpectedResponse) { try ReleaseVersionFile.version(from: Data(body.utf8)) }
  }
}
