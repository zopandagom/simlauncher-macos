import Foundation
import Testing
@testable import Core

/// 카탈로그 해석이 거절하는 규칙 (docs/CATALOG.md "앱이 거절하는 경우").
struct BuildCatalogProblemTests {
  struct ProblemCase: Sendable, CustomTestStringConvertible {
    let label: String
    let data: Data
    let expected: BuildCatalogProblem

    var testDescription: String {
      self.label
    }
  }

  struct URLCase: Sendable, CustomTestStringConvertible {
    let raw: String
    let problem: DownloadURLProblem

    var testDescription: String {
      self.raw.debugDescription
    }
  }

  @Test(
    "JSON 객체가 아니면 notJSONObject",
    arguments: [
      "",
      "<html>login</html>",
      "[]",
      "\"catalog\"",
      "{",
      // 스캐너가 먼저 거절하는 600 단계 배열.
      "\(String(repeating: "[", count: 600))\(String(repeating: "]", count: 600))",
    ]
  )
  func notJSONObject(raw: String) {
    #expect(catalogProblem(Data(raw.utf8)) == .notJSONObject)
  }

  @Test("잘못된 UTF-8 바이트가 든 데이터는 notJSONObject")
  func notJSONObjectInvalidUTF8() {
    // {"<0xFF>":1}
    let data = Data([0x7B, 0x22, 0xFF, 0x22, 0x3A, 0x31, 0x7D])

    #expect(catalogProblem(data) == .notJSONObject)
  }

  @Test("값의 중첩이 32 단계를 넘으면 객체·배열 모두 notJSONObject", arguments: [33, 64], [true, false])
  func nestingTooDeep(depth: Int, objects: Bool) {
    let extra = CatalogText.nested(depth: depth, objects: objects)
    let data = Data(#"{"schemaVersion":1,"apps":[],"extra":\#(extra)}"#.utf8)

    #expect(catalogProblem(data) == .notJSONObject)
  }

  @Test(
    "schemaVersion 이 없거나 null 이면 missingField(.schemaVersion, .root)",
    arguments: [#"{"apps":[]}"#, #"{"schemaVersion":null,"apps":[]}"#]
  )
  func schemaVersionMissing(raw: String) {
    #expect(catalogProblem(Data(raw.utf8)) == .missingField(.schemaVersion, position: .root))
  }

  @Test(
    "schemaVersion 이 정수가 아니거나 Int 범위 밖이면 wrongType",
    arguments: [#""1""#, "1.5", "true", "[1]", "99999999999999999999"]
  )
  func schemaVersionWrongType(value: String) {
    let data = Data(#"{"schemaVersion":\#(value),"apps":[]}"#.utf8)

    #expect(catalogProblem(data) == .wrongType(.schemaVersion, position: .root))
  }

  @Test("1 이 아닌 정수 schemaVersion 은 unsupportedSchemaVersion", arguments: [0, 2, -1])
  func unsupportedSchemaVersion(version: Int) {
    let data = Data(#"{"schemaVersion":\#(version),"apps":[]}"#.utf8)

    #expect(catalogProblem(data) == .unsupportedSchemaVersion(version))
  }

  @Test("정수가 되는 숫자 2.0·2e0 은 unsupportedSchemaVersion(2)", arguments: ["2.0", "2e0"])
  func schemaVersionIntegralNumberUnsupported(value: String) {
    let data = Data(#"{"schemaVersion":\#(value),"apps":[]}"#.utf8)

    #expect(catalogProblem(data) == .unsupportedSchemaVersion(2))
  }

  @Test("schemaVersion 은 64비트 정수 끝까지 정수로 읽고 그 밖은 wrongType")
  func schemaVersionInt64Bounds() {
    func problem(_ value: String) -> BuildCatalogProblem? {
      catalogProblem(Data(#"{"schemaVersion":\#(value),"apps":[]}"#.utf8))
    }

    #expect(problem("9223372036854775807") == .unsupportedSchemaVersion(Int.max))
    #expect(problem("-9223372036854775808") == .unsupportedSchemaVersion(Int.min))
    #expect(problem("9223372036854775808") == .wrongType(.schemaVersion, position: .root))
    #expect(problem("-9223372036854775809") == .wrongType(.schemaVersion, position: .root))
  }

  @Test("schemaVersion 이 2 면 나머지 구조가 달라도 unsupportedSchemaVersion(2)")
  func schemaVersionCheckedFirst() {
    let data = Data(#"{"schemaVersion":2,"apps":"다른 구조"}"#.utf8)

    #expect(catalogProblem(data) == .unsupportedSchemaVersion(2))
  }

  @Test("apps 가 없거나 null 이면 missingField, 배열이 아니면 wrongType, 항목이 객체가 아니면(null·배열·문자열) 그 인덱스의 wrongType(.apps)")
  func appsMissingOrWrongType() {
    #expect(catalogProblem(Data(#"{"schemaVersion":1}"#.utf8)) == .missingField(.apps, position: .root))
    #expect(catalogProblem(Data(#"{"schemaVersion":1,"apps":null}"#.utf8)) == .missingField(.apps, position: .root))
    #expect(catalogProblem(Data(#"{"schemaVersion":1,"apps":{}}"#.utf8)) == .wrongType(.apps, position: .root))
    for item in ["null", "[]", #""x""#] {
      let data = CatalogText.catalog([CatalogText.app(id: "a"), item])
      #expect(catalogProblem(data) == .wrongType(.apps, position: catalogPosition(app: 1, nil)))
    }
  }

  @Test("필수 필드가 없거나 null 이면 missingField 와 위치", arguments: Self.missingFieldCases)
  func requiredFieldMissing(testCase: ProblemCase) {
    #expect(catalogProblem(testCase.data) == testCase.expected)
  }

  @Test("필드 타입이 다르면 필수·선택 모두 wrongType", arguments: Self.wrongTypeCases)
  func fieldWrongType(testCase: ProblemCase) {
    #expect(catalogProblem(testCase.data) == testCase.expected)
  }

  @Test("앱·버전 이름이 공백·개행뿐이면 emptyField(.name)", arguments: ["  ", "\n", " \t\n "], [false, true])
  func emptyName(raw: String, inVersion: Bool) {
    let name = CatalogText.quoted(raw)
    let data: Data
    let position: BuildCatalogProblem.Position
    if inVersion {
      data = CatalogText.catalog([CatalogText.app(versions: [CatalogText.version(replacing: ["name": name])])])
      position = catalogPosition(app: 0, "a", version: 0, "v1")
    } else {
      data = CatalogText.catalog([CatalogText.app(replacing: ["name": name])])
      position = catalogPosition(app: 0, "a")
    }

    #expect(catalogProblem(data) == .emptyField(.name, position: position))
  }

  @Test(
    "id 형식이 아니면 invalidID (앱·버전)",
    arguments: [
      "", " a", "a ", "a\n", "my app", "-a", ".a", "_a", "a/b", "a+b", "앱", "café", "ａ",
      String(repeating: "a", count: 129),
      // 영문·숫자 범위 바로 밖의 글자.
      "a`b", "a{b", "a@b", "a[b", "a:b",
    ],
    [false, true]
  )
  func invalidID(raw: String, inVersion: Bool) {
    let data: Data
    let position: BuildCatalogProblem.Position
    if inVersion {
      data = CatalogText.catalog([CatalogText.app(versions: [CatalogText.version(id: raw)])])
      position = catalogPosition(app: 0, "a", version: 0, nil)
    } else {
      data = CatalogText.catalog([CatalogText.app(id: raw)])
      position = catalogPosition(app: 0, nil)
    }

    #expect(catalogProblem(data) == .invalidID(position: position))
  }

  @Test("앱 id 가 겹치면 뒤 앱의 인덱스·id 로 duplicateAppID")
  func duplicateAppID() {
    let data = CatalogText.catalog([CatalogText.app(id: "a"), CatalogText.app(id: "b"), CatalogText.app(id: "a")])

    #expect(catalogProblem(data) == .duplicateAppID(position: catalogPosition(app: 2, "a")))
  }

  @Test("앱 id 는 대소문자를 무시하고 비교한다: sample 뒤 Sample 은 뒤 앱 위치(appID \"Sample\")의 duplicateAppID")
  func duplicateAppIDIgnoresCase() {
    let data = CatalogText.catalog([CatalogText.app(id: "sample"), CatalogText.app(id: "Sample")])

    #expect(catalogProblem(data) == .duplicateAppID(position: catalogPosition(app: 1, "Sample")))
  }

  @Test(
    "같은 앱 안 버전 id 가 (대소문자 무시) 겹치면 뒤 버전 위치로 duplicateVersionID",
    arguments: zip(["build-1", "build-1"], ["build-1", "Build-1"])
  )
  func duplicateVersionID(first: String, second: String) {
    let versions = [CatalogText.version(id: first), CatalogText.version(id: second)]
    let data = CatalogText.catalog([CatalogText.app(versions: versions)])

    #expect(catalogProblem(data) == .duplicateVersionID(position: catalogPosition(app: 0, "a", version: 1, second)))
  }

  @Test(
    "날짜 형식의 글자 형식이 아니거나 값이 범위 밖이면 invalidCreatedAt",
    arguments: Self.invalidCreatedAtInputs
  )
  func invalidCreatedAt(raw: String) {
    let data = CatalogText.catalog([CatalogText.app(versions: [CatalogText.version(createdAt: raw)])])

    #expect(catalogProblem(data) == .invalidCreatedAt(position: catalogPosition(app: 0, "a", version: 0, "v1")))
  }

  @Test(
    "빌드 URL 이 DownloadURL 검사에 걸리면 그 문제와 함께 invalidBuildURL",
    arguments: [
      URLCase(raw: "http://example.com/a.zip", problem: .notHTTPS),
      URLCase(raw: "builds/a.zip", problem: .notHTTPS),
      URLCase(raw: "/a.zip", problem: .notHTTPS),
      URLCase(raw: "./a.zip", problem: .notHTTPS),
      URLCase(raw: "//example.com/a.zip", problem: .notHTTPS),
      URLCase(raw: "https://user:pw@example.com/a.zip", problem: .hasCredentials),
      URLCase(raw: "https://@example.com/a", problem: .hasCredentials),
      URLCase(raw: "", problem: .empty),
      URLCase(raw: "  ", problem: .empty),
      URLCase(raw: "https://", problem: .missingHost),
      URLCase(raw: "https://exa mple.com/a.zip", problem: .malformed),
    ]
  )
  func invalidBuildURL(testCase: URLCase) {
    let version = CatalogText.version(replacing: ["buildURL": CatalogText.quoted(testCase.raw)])
    let data = CatalogText.catalog([CatalogText.app(versions: [version])])

    let position = catalogPosition(app: 0, "a", version: 0, "v1")
    #expect(catalogProblem(data) == .invalidBuildURL(testCase.problem, position: position))
  }

  @Test("틀린 버전이 둘이면 정렬 순서가 아니라 파일 순서로 첫 번째를 알린다")
  func firstBadVersionInFileOrder() {
    let http = ["buildURL": #""http://example.com/a.zip""#]
    let versions = [
      CatalogText.version(id: "old", createdAt: "2020-01-01T00:00:00Z", replacing: http),
      CatalogText.version(id: "new", createdAt: "2026-01-01T00:00:00Z", replacing: http),
    ]

    let problem = catalogProblem(CatalogText.catalog([CatalogText.app(versions: versions)]))

    #expect(problem == .invalidBuildURL(.notHTTPS, position: catalogPosition(app: 0, "a", version: 0, "old")))
  }

  @Test("두 번째 앱의 세 번째 버전 문제는 appIndex 1·appID·versionIndex 2·versionID 를 담는다")
  func problemPositionNamesIndexAndID() {
    let secondVersions = [
      CatalogText.version(id: "v1"),
      CatalogText.version(id: "v2"),
      CatalogText.version(id: "v3", createdAt: "2026-10-21"),
    ]
    let apps = [
      CatalogText.app(id: "first", versions: [CatalogText.version(id: "v1")]),
      CatalogText.app(id: "second", versions: secondVersions),
    ]

    let problem = catalogProblem(CatalogText.catalog(apps))

    #expect(problem == .invalidCreatedAt(position: catalogPosition(app: 1, "second", version: 2, "v3")))
  }

  @Test("문제가 여럿이면 검사 순서상 첫 문제 하나: 첫 앱의 빌드 URL 문제가 둘째 앱의 id 문제보다 먼저, 같은 버전에서 createdAt 이 buildURL 보다 먼저")
  func firstProblemInDocumentOrder() {
    let httpVersion = CatalogText.version(replacing: ["buildURL": #""http://example.com/a.zip""#])
    let acrossApps = CatalogText.catalog([CatalogText.app(versions: [httpVersion]), CatalogText.app(id: "bad id")])
    let position = catalogPosition(app: 0, "a", version: 0, "v1")
    #expect(catalogProblem(acrossApps) == .invalidBuildURL(.notHTTPS, position: position))

    let both = CatalogText.version(createdAt: "2026-10-21", replacing: ["buildURL": #""http://example.com/a.zip""#])
    let inVersion = CatalogText.catalog([CatalogText.app(versions: [both])])
    #expect(catalogProblem(inVersion) == .invalidCreatedAt(position: position))
  }
}

extension BuildCatalogProblemTests {
  /// `invalidCreatedAt` 의 입력.
  static let invalidCreatedAtInputs: [String] = [
    // 글자 형식 밖
    "2026-10-21T04:08:49",
    "2026-10-21",
    "2026-10-21 04:08:49Z",
    "2026-10-21t04:08:49Z",
    "2026-10-21T04:08:49z",
    "20261021T040849Z",
    " 2026-10-21T04:08:49Z",
    "2026-10-21T04:08:49Z ",
    "2026-10-21T04:08:49Z\n",
    "2026-10-21T04:08:49Zabc",
    "2026-10-21T13:08:49+09:00junk",
    "2026-10-21T13:08:49+09",
    "2026-10-21T13:08:49+0900",
    "2026-1-2T4:8:9Z",
    "2026-10-21T04:08:49Z+09:00",
    "2026-10-21T04:08:49.Z",
    "2026-10-21T04:08:49,073Z",
    "2026-10-21T04:08:49.1234567890Z",
    "2026-10-21T13:08:49+09:00+09:00",
    "2026-10-21T04:08:49+09:0:",
    "2026-10-21T04:08:49+09:0/",
    "２０２６-10-21T04:08:49Z",
    "",
    // 글자 형식 안, 값 범위 밖
    "2026-13-01T00:00:00Z",
    "2026-10-32T00:00:00Z",
    "2026-00-10T04:08:49Z",
    "2026-10-00T04:08:49Z",
    "2026-99-01T00:00:00Z",
    "2026-10-99T00:00:00Z",
    "2026-02-29T00:00:00Z",
    "2100-02-29T00:00:00Z",
    "1900-02-29T00:00:00Z",
    "2026-02-30T00:00:00Z",
    "2026-04-31T00:00:00Z",
    "2026-06-31T00:00:00Z",
    "2026-09-31T00:00:00Z",
    "2026-11-31T00:00:00Z",
    "2200-02-29T00:00:00Z",
    "1800-02-29T00:00:00Z",
    "2026-12-32T00:00:00Z",
    "2026-10-21T24:00:00Z",
    "2026-10-21T00:60:00Z",
    "2026-10-21T23:59:60Z",
    "2026-10-21T04:08:49+17:60",
    "2026-10-21T04:08:49+18:01",
    "2026-10-21T04:08:49-18:01",
    "2026-10-21T04:08:49+19:00",
    "2026-10-21T04:08:49-19:00",
    "2026-10-21T04:08:49+23:59",
    "2026-10-21T04:08:49+99:00",
    "1582-12-31T23:59:59Z",
    "0000-01-01T00:00:00Z",
  ]

  /// `fieldCheckOrder` 의 한 단계: 지금 나와야 할 문제와, 그다음 단계로 가려고 고칠 필드.
  struct CheckStep {
    let expected: BuildCatalogProblem
    let key: String
    let fix: String
  }

  @Test("Double 범위를 넘는 큰 숫자나 짝 없는 서러게이트는 어디에 있든 notJSONObject", arguments: Self.unreadableCases)
  func unreadableValuesRejectAnywhere(testCase: ProblemCase) {
    #expect(catalogProblem(testCase.data) == testCase.expected)
  }

  @Test(
    "필드 이름은 대소문자·표기를 구분해 SchemaVersion·schema_version 은 없는 것(missingField(.schemaVersion))",
    arguments: [#"{"SchemaVersion":1,"apps":[]}"#, #"{"schema_version":1,"apps":[]}"#]
  )
  func fieldNamesAreCaseSensitive(raw: String) {
    #expect(catalogProblem(Data(raw.utf8)) == .missingField(.schemaVersion, position: .root))
  }

  @Test("중첩 단계는 최상위부터 센다: 버전 안 모르는 필드의 가장 안쪽 값이 33단계면 notJSONObject (객체·배열)", arguments: [true, false])
  func nestingCountsFromRootInVersion(objects: Bool) {
    // 버전의 필드 값이 5단계라 nested 29단계 = 33단계.
    let version = CatalogText.version(replacing: ["extra": CatalogText.nested(depth: 29, objects: objects)])

    #expect(catalogProblem(CatalogText.catalog([CatalogText.app(versions: [version])])) == .notJSONObject)
  }

  @Test("검사 순서는 문서대로다: 모든 필드가 틀린 앱·버전에서 앞 필드를 하나씩 고치면 다음 필드의 문제가 나온다")
  func fieldCheckOrder() {
    let first = CatalogText.app(id: "a", versions: [CatalogText.version(id: "v1")])
    var appFields: [String: String] = ["id": #""bad id""#, "name": #"" ""#, "versions": "{}"]
    for step in Self.appCheckSteps {
      let data = CatalogText.catalog([first, CatalogText.app(replacing: appFields)])
      #expect(catalogProblem(data) == step.expected, "앱 \(step.key)")
      appFields[step.key] = step.fix
    }
    #expect(catalogProblem(CatalogText.catalog([first, CatalogText.app(replacing: appFields)])) == nil)

    var versionFields: [String: String] = [
      "id": #""bad id""#, "name": #"" ""#, "branch": "1", "tag": "1", "buildNumber": "1",
      "createdAt": #""x""#, "buildURL": #""http://example.com/v2.zip""#,
    ]
    for step in Self.versionCheckSteps {
      let versions = [CatalogText.version(id: "v1"), CatalogText.version(replacing: versionFields)]
      let data = CatalogText.catalog([CatalogText.app(id: "a", versions: versions)])
      #expect(catalogProblem(data) == step.expected, "버전 \(step.key)")
      versionFields[step.key] = step.fix
    }
    let fixed = [CatalogText.version(id: "v1"), CatalogText.version(replacing: versionFields)]
    #expect(catalogProblem(CatalogText.catalog([CatalogText.app(id: "a", versions: fixed)])) == nil)
  }

  /// 둘째 앱(첫 앱 "a" 뒤)의 검사 순서.
  static let appCheckSteps: [CheckStep] = [
    CheckStep(expected: .invalidID(position: catalogPosition(app: 1, nil)), key: "id", fix: #""A""#),
    CheckStep(expected: .duplicateAppID(position: catalogPosition(app: 1, "A")), key: "id", fix: #""b""#),
    CheckStep(expected: .emptyField(.name, position: catalogPosition(app: 1, "b")), key: "name", fix: #""B""#),
    CheckStep(expected: .wrongType(.versions, position: catalogPosition(app: 1, "b")), key: "versions", fix: "[]"),
  ]

  /// 첫 앱의 둘째 버전(첫 버전 "v1" 뒤)의 검사 순서.
  static let versionCheckSteps: [CheckStep] = {
    let versionPosition = catalogPosition(app: 0, "a", version: 1, "v2")
    return [
      CheckStep(
        expected: .invalidID(position: catalogPosition(app: 0, "a", version: 1, nil)),
        key: "id",
        fix: #""V1""#
      ),
      CheckStep(
        expected: .duplicateVersionID(position: catalogPosition(app: 0, "a", version: 1, "V1")),
        key: "id",
        fix: #""v2""#
      ),
      CheckStep(expected: .emptyField(.name, position: versionPosition), key: "name", fix: #""V2""#),
      CheckStep(expected: .wrongType(.branch, position: versionPosition), key: "branch", fix: #""main""#),
      CheckStep(expected: .wrongType(.tag, position: versionPosition), key: "tag", fix: #""v2""#),
      CheckStep(expected: .wrongType(.buildNumber, position: versionPosition), key: "buildNumber", fix: #""2""#),
      CheckStep(
        expected: .invalidCreatedAt(position: versionPosition),
        key: "createdAt",
        fix: #""2026-10-21T04:08:49Z""#
      ),
      CheckStep(
        expected: .invalidBuildURL(.notHTTPS, position: versionPosition),
        key: "buildURL",
        fix: #""https://example.com/v2.zip""#
      ),
    ]
  }()

  /// 표준 JSON 이지만 Foundation 이 값으로 읽지 못하는 것. 모르는 필드 안이어도 카탈로그 전체를 거절한다.
  static let unreadableCases: [ProblemCase] = {
    let longInteger = String(repeating: "9", count: 400)
    let topLevel: [(label: String, value: String)] = [
      ("extra 1e400", "1e400"),
      ("extra -1e400", "-1e400"),
      ("extra 400 자리 정수", longInteger),
      (#"extra "\ud800""#, #""\ud800""#),
      (#"extra 키 "\ud800""#, #"{"\ud800":1}"#),
    ]
    var cases: [ProblemCase] = topLevel.map { entry in
      let data = Data(#"{"schemaVersion":1,"apps":[],"extra":\#(entry.value)}"#.utf8)
      return ProblemCase(label: entry.label, data: data, expected: .notJSONObject)
    }
    let inVersion: [(label: String, replacing: [String: String])] = [
      ("버전 size 1e400", ["size": "1e400"]),
      ("버전 buildNumber 1e400", ["buildNumber": "1e400"]),
      (#"버전 branch "\ud800""#, ["branch": #""\ud800""#]),
    ]
    for entry in inVersion {
      let version = CatalogText.version(replacing: entry.replacing)
      let data = CatalogText.catalog([CatalogText.app(versions: [version])])
      cases.append(ProblemCase(label: entry.label, data: data, expected: .notJSONObject))
    }
    let schemaVersion = Data(#"{"schemaVersion":1e400,"apps":[]}"#.utf8)
    cases.append(ProblemCase(label: "schemaVersion 1e400", data: schemaVersion, expected: .notJSONObject))
    return cases
  }()

  /// 앱 id·name·versions 와 버전 id·name·createdAt·buildURL 을 각각 빼거나 null 로.
  static let missingFieldCases: [ProblemCase] = {
    var cases: [ProblemCase] = []
    let appFields: [(field: BuildCatalogProblem.Field, position: BuildCatalogProblem.Position)] = [
      (.id, catalogPosition(app: 0, nil)),
      (.name, catalogPosition(app: 0, "a")),
      (.versions, catalogPosition(app: 0, "a")),
    ]
    for entry in appFields {
      let key = entry.field.rawValue
      let expected = BuildCatalogProblem.missingField(entry.field, position: entry.position)
      let absent = CatalogText.catalog([CatalogText.app(removing: [key])])
      let nullValue = CatalogText.catalog([CatalogText.app(replacing: [key: "null"])])
      cases.append(ProblemCase(label: "앱 \(key) 없음", data: absent, expected: expected))
      cases.append(ProblemCase(label: "앱 \(key) null", data: nullValue, expected: expected))
    }
    let versionFields: [BuildCatalogProblem.Field] = [.id, .name, .createdAt, .buildURL]
    for field in versionFields {
      let key = field.rawValue
      let position = catalogPosition(app: 0, "a", version: 0, field == .id ? nil : "v1")
      let expected = BuildCatalogProblem.missingField(field, position: position)
      let absent = CatalogText.catalog([CatalogText.app(versions: [CatalogText.version(removing: [key])])])
      let nullValue = CatalogText.catalog([CatalogText.app(versions: [CatalogText.version(replacing: [key: "null"])])])
      cases.append(ProblemCase(label: "버전 \(key) 없음", data: absent, expected: expected))
      cases.append(ProblemCase(label: "버전 \(key) null", data: nullValue, expected: expected))
    }
    return cases
  }()

  /// 앱·버전 필드에 다른 JSON 타입. `id` 타입 오류는 위치에 그 객체의 id 가 없다.
  static let wrongTypeCases: [ProblemCase] = {
    let appPosition = catalogPosition(app: 0, "a")
    let versionPosition = catalogPosition(app: 0, "a", version: 0, "v1")
    var cases: [ProblemCase] = [
      ProblemCase(
        label: "앱 id 숫자",
        data: CatalogText.catalog([CatalogText.app(replacing: ["id": "8812345678"])]),
        expected: .wrongType(.id, position: catalogPosition(app: 0, nil))
      ),
      ProblemCase(
        label: "앱 name 숫자",
        data: CatalogText.catalog([CatalogText.app(replacing: ["name": "1"])]),
        expected: .wrongType(.name, position: appPosition)
      ),
      ProblemCase(
        label: "앱 versions 객체",
        data: CatalogText.catalog([CatalogText.app(replacing: ["versions": "{}"])]),
        expected: .wrongType(.versions, position: appPosition)
      ),
      ProblemCase(
        label: "버전 id 숫자",
        data: CatalogText.catalog([CatalogText.app(versions: [CatalogText.version(replacing: ["id": "42"])])]),
        expected: .wrongType(.id, position: catalogPosition(app: 0, "a", version: 0, nil))
      ),
    ]
    for item in ["null", "[]", #""x""#] {
      cases.append(
        ProblemCase(
          label: "versions 항목 \(item)",
          data: CatalogText.catalog([CatalogText.app(versions: [item])]),
          expected: .wrongType(.versions, position: catalogPosition(app: 0, "a", version: 0, nil))
        )
      )
    }
    let versionValues: [(field: BuildCatalogProblem.Field, value: String)] = [
      (.name, "true"),
      (.branch, "1"),
      (.branch, "{}"),
      (.tag, "true"),
      (.tag, "[]"),
      (.buildNumber, "42"),
      (.createdAt, "1792555729"),
      (.buildURL, "{}"),
    ]
    for entry in versionValues {
      let version = CatalogText.version(replacing: [entry.field.rawValue: entry.value])
      cases.append(
        ProblemCase(
          label: "버전 \(entry.field.rawValue) \(entry.value)",
          data: CatalogText.catalog([CatalogText.app(versions: [version])]),
          expected: .wrongType(entry.field, position: versionPosition)
        )
      )
    }
    return cases
  }()
}
