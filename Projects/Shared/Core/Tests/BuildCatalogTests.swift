import Foundation
import Testing
@testable import Core

/// 카탈로그 해석이 받아들이는 규칙 (docs/CATALOG.md).
struct BuildCatalogTests {
  struct AcceptedDate: Sendable, CustomTestStringConvertible {
    let raw: String
    let milliseconds: Int64

    var testDescription: String {
      self.raw.debugDescription
    }
  }

  /// 2026-10-21T04:08:49Z.
  static let baseMilliseconds: Int64 = 1_792_555_729_000

  @Test("모르는 필드는 최상위·앱·버전 어디에 있어도, 값이 객체·배열·null 이어도 무시한다")
  func unknownFieldsIgnored() throws {
    let data = Data(
      #"""
      {
        "schemaVersion": 1,
        "extra": {"nested": [1, {"deep": true}]},
        "note": null,
        "apps": [
          {
            "id": "a",
            "name": "A",
            "owner": [1, "two"],
            "versions": [
              {
                "id": "v1",
                "name": "V1",
                "size": 123,
                "meta": {"key": "value"},
                "draft": null,
                "createdAt": "2026-10-21T04:08:49Z",
                "buildURL": "https://example.com/a.zip"
              }
            ]
          }
        ]
      }
      """#.utf8
    )

    let catalog = try BuildCatalog(jsonData: data)

    let buildURL = try #require(DownloadURL("https://example.com/a.zip"))
    let version = BuildCatalog.Version(
      id: BuildCatalog.VersionID("v1"),
      name: "V1",
      branch: nil,
      tag: nil,
      buildNumber: nil,
      createdAt: Date(timeIntervalSince1970: 1_792_555_729),
      buildURL: buildURL
    )
    let app = BuildCatalog.App(id: BuildCatalog.AppID("a"), name: "A", versions: [version])
    #expect(catalog == BuildCatalog(schemaVersion: 1, apps: [app]))
  }

  @Test("앱이 없는 카탈로그와 버전이 없는 앱도 읽는다")
  func emptyAppsAndVersions() throws {
    let empty = try BuildCatalog(jsonData: CatalogText.catalog([]))
    #expect(empty.apps.isEmpty)

    let noVersions = try BuildCatalog(jsonData: CatalogText.catalog([CatalogText.app(id: "a")]))
    #expect(noVersions.apps.map(\.id.rawValue) == ["a"])
    #expect(noVersions.apps.first?.versions.isEmpty == true)
  }

  @Test("앱은 파일 순서 그대로다 (id·이름 순서와 무관)")
  func appsKeepFileOrder() throws {
    let apps = [
      CatalogText.app(id: "c", replacing: ["name": #""Zeta""#]),
      CatalogText.app(id: "a", replacing: ["name": #""Alpha""#]),
      CatalogText.app(id: "B", replacing: ["name": #""Mid""#]),
    ]

    let catalog = try BuildCatalog(jsonData: CatalogText.catalog(apps))

    #expect(catalog.apps.map(\.id.rawValue) == ["c", "a", "B"])
    #expect(catalog.apps.map(\.name) == ["Zeta", "Alpha", "Mid"])
  }

  @Test("버전은 생성 시각이 늦은 것부터다 (시간대가 달라도, 같은 초 안의 소수 초 차이도 시각으로 비교)")
  func versionsNewestFirst() throws {
    let versions = [
      CatalogText.version(id: "c", createdAt: "2026-10-21T04:08:48Z"),
      CatalogText.version(id: "d", createdAt: "2026-10-21T13:08:49.073+09:00"),
      CatalogText.version(id: "b", createdAt: "2026-10-21T04:08:50Z"),
      CatalogText.version(id: "a", createdAt: "2026-10-21T04:08:49.072Z"),
    ]

    let catalog = try BuildCatalog(jsonData: CatalogText.catalog([CatalogText.app(versions: versions)]))

    let app = try #require(catalog.apps.first)
    #expect(app.versions.map(\.id.rawValue) == ["b", "d", "a", "c"])
  }

  @Test("생성 시각이 같으면 id 오름차순이다 (파일에 내림차순으로 적어도)")
  func versionsTieBreakByID() throws {
    let versions = [
      CatalogText.version(id: "b", createdAt: "2026-10-21T04:08:49Z"),
      CatalogText.version(id: "a", createdAt: "2026-10-21T13:08:49+09:00"),
    ]

    let catalog = try BuildCatalog(jsonData: CatalogText.catalog([CatalogText.app(versions: versions)]))

    let app = try #require(catalog.apps.first)
    #expect(app.versions.map(\.id.rawValue) == ["a", "b"])
  }

  @Test("선택 필드가 없거나 null 이거나 공백·개행뿐이면 nil 이다")
  func optionalFieldsAbsentNullOrBlankAreNil() throws {
    let versions = [
      CatalogText.version(id: "v1"),
      CatalogText.version(id: "v2", replacing: ["branch": "null", "tag": "null", "buildNumber": "null"]),
      CatalogText.version(id: "v3", replacing: ["branch": #""  ""#, "tag": #""\n""#, "buildNumber": #"" \t\n ""#]),
    ]

    let catalog = try BuildCatalog(jsonData: CatalogText.catalog([CatalogText.app(versions: versions)]))

    let app = try #require(catalog.apps.first)
    #expect(app.versions.map(\.id.rawValue) == ["v1", "v2", "v3"])
    #expect(app.versions.map(\.branch) == [nil, nil, nil])
    #expect(app.versions.map(\.tag) == [nil, nil, nil])
    #expect(app.versions.map(\.buildNumber) == [nil, nil, nil])
  }

  @Test("앱·버전 이름, 선택 필드, 빌드 URL 은 앞뒤 공백·개행을 뺀 값이다")
  func stringsAreTrimmed() throws {
    let version = CatalogText.version(
      replacing: [
        "name": #""\tV1 ""#,
        "branch": #"" main\n""#,
        "tag": #"" v1 ""#,
        "buildNumber": #"" 42 ""#,
        "buildURL": #""  https://example.com/a.zip\n""#,
      ]
    )
    let app = CatalogText.app(versions: [version], replacing: ["name": #""  App \n""#])

    let catalog = try BuildCatalog(jsonData: CatalogText.catalog([app]))

    let parsedApp = try #require(catalog.apps.first)
    #expect(parsedApp.name == "App")
    let parsed = try #require(parsedApp.versions.first)
    #expect(parsed.name == "V1")
    #expect(parsed.branch == "main")
    #expect(parsed.tag == "v1")
    #expect(parsed.buildNumber == "42")
    #expect(parsed.buildURL.url.absoluteString == "https://example.com/a.zip")
  }

  @Test(
    "날짜 형식의 시각은 소수 초(1~9 자리)·시간대 표기와 관계없이 읽는다",
    arguments: Self.acceptedDates
  )
  func createdAtAccepted(testCase: AcceptedDate) throws {
    let data = CatalogText.catalog([CatalogText.app(versions: [CatalogText.version(createdAt: testCase.raw)])])

    let catalog = try BuildCatalog(jsonData: data)

    let version = try #require(catalog.apps.first?.versions.first)
    #expect(milliseconds(version.createdAt) == testCase.milliseconds)
  }

  @Test(
    "id 는 영문·숫자로 시작하고 영문·숫자·. _ - 로 128 자까지다",
    arguments: [
      "a", "A", "0", "8812345678", "com.example.app", "a_b-c.d", String(repeating: "a", count: 128),
      // 규격 문서의 예.
      "com.example.sample", "sample-app", "build-42", "1.3.0-42",
      // 글자 범위의 끝.
      "z", "Z", "9", "zZ9", "a.z_Z-9",
    ]
  )
  func validIDs(id: String) throws {
    let data = CatalogText.catalog([CatalogText.app(id: id, versions: [CatalogText.version(id: id)])])

    let catalog = try BuildCatalog(jsonData: data)

    let app = try #require(catalog.apps.first)
    #expect(app.id.rawValue == id)
    #expect(app.versions.map(\.id.rawValue) == [id])
  }

  @Test("버전 id 는 다른 앱과는 겹쳐도 된다")
  func sameVersionIDInDifferentApps() throws {
    let apps = [
      CatalogText.app(id: "a", versions: [CatalogText.version(id: "build-1")]),
      CatalogText.app(id: "b", versions: [CatalogText.version(id: "build-1")]),
    ]

    let catalog = try BuildCatalog(jsonData: CatalogText.catalog(apps))

    #expect(catalog.apps.map { $0.versions.map(\.id.rawValue) } == [["build-1"], ["build-1"]])
  }

  @Test("모르는 필드 안의 값이 중첩 32 단계까지면 무시하고 읽는다 (객체·배열)", arguments: [true, false])
  func nestingWithinLimitIgnored(objects: Bool) throws {
    let extra = CatalogText.nested(depth: 32, objects: objects)
    let data = Data(#"{"schemaVersion":1,"apps":[],"extra":\#(extra)}"#.utf8)

    let catalog = try BuildCatalog(jsonData: data)

    #expect(catalog.apps.isEmpty)
  }

  @Test("버전 안 모르는 필드는 5단계부터 세어, 가장 안쪽 값이 32단계까지면 읽는다 (객체·배열)", arguments: [true, false])
  func nestingWithinLimitInVersion(objects: Bool) throws {
    // apps(1) → 앱(2) → versions(3) → 버전(4) → 버전의 필드 값(5). nested 의 가장 안쪽 값은 필드 값에서 28단계 = 32단계.
    let version = CatalogText.version(replacing: ["extra": CatalogText.nested(depth: 28, objects: objects)])

    let catalog = try BuildCatalog(jsonData: CatalogText.catalog([CatalogText.app(versions: [version])]))

    #expect(catalog.apps.first?.versions.count == 1)
  }

  /// Foundation 의 동작이다. 이 테스트가 실패하면 docs/CATALOG.md 1절 "같은 키를 두 번" 문장을 함께 고친다.
  @Test("같은 객체에 같은 키가 두 번이면 첫 값을 쓴다 (검출하지 않음)")
  func duplicateKeyUsesFirstValue() throws {
    let app = #"{"id":"a","name":"First","name":"Second","versions":[]}"#
    let names = try BuildCatalog(jsonData: CatalogText.catalog([app]))
    #expect(names.apps.map(\.name) == ["First"])

    let firstIsOne = Data(#"{"schemaVersion":1,"schemaVersion":3,"apps":[]}"#.utf8)
    #expect(catalogProblem(firstIsOne) == nil)

    let firstIsThree = Data(#"{"schemaVersion":3,"schemaVersion":1,"apps":[]}"#.utf8)
    #expect(catalogProblem(firstIsThree) == .unsupportedSchemaVersion(3))
  }

  @Test("소수 초는 1 마이크로초 차이까지 구분한다")
  func fractionalSecondsDistinguishMicroseconds() throws {
    let versions = [
      CatalogText.version(id: "v1", createdAt: "2026-10-21T04:08:49.123456Z"),
      CatalogText.version(id: "v2", createdAt: "2026-10-21T04:08:49.000001Z"),
      CatalogText.version(id: "v3", createdAt: "2026-10-21T04:08:49.123457Z"),
    ]

    let catalog = try BuildCatalog(jsonData: CatalogText.catalog([CatalogText.app(versions: versions)]))

    let app = try #require(catalog.apps.first)
    #expect(app.versions.map(\.id.rawValue) == ["v3", "v1", "v2"])
    let microsecondsByID: [String: Int64] = Dictionary(
      uniqueKeysWithValues: app.versions.map { ($0.id.rawValue, microseconds($0.createdAt)) }
    )
    #expect(microsecondsByID["v1"] == 1_792_555_729_123_456)
    #expect(microsecondsByID["v2"] == 1_792_555_729_000_001)
    #expect(microsecondsByID["v3"] == 1_792_555_729_123_457)
  }

  @Test("같은 시각이면 id 를 ASCII 순서(대소문자 구분)로: B 가 a 보다 앞")
  func versionsTieBreakIsCaseSensitiveASCII() throws {
    let versions = [CatalogText.version(id: "a"), CatalogText.version(id: "B")]

    let catalog = try BuildCatalog(jsonData: CatalogText.catalog([CatalogText.app(versions: versions)]))

    #expect(catalog.apps.first?.versions.map(\.id.rawValue) == ["B", "a"])
  }

  @Test("공백으로 이어 붙인 두 주소는 경로의 %20 으로 읽혀 통과한다")
  func buildURLWithSpaceIsPercentEncoded() throws {
    let version = CatalogText.version(replacing: ["buildURL": #""https://a.example/x.zip https://b.example""#])

    let catalog = try BuildCatalog(jsonData: CatalogText.catalog([CatalogText.app(versions: [version])]))

    let parsed = try #require(catalog.apps.first?.versions.first)
    #expect(parsed.buildURL.url.absoluteString == "https://a.example/x.zip%20https://b.example")
  }

  @Test(
    "윤년은 4 의 배수, 100 의 배수는 평년, 400 의 배수는 윤년",
    arguments: zip(
      [2024, 2026, 2000, 2100, 1900, 2400, 0, 2200, 1800, 2600, 1600],
      [true, false, true, false, false, true, true, false, false, false, true]
    )
  )
  func leapYearRule(year: Int, expected: Bool) {
    #expect(BuildCatalogReader.isLeapYear(year) == expected)
  }

  /// Foundation 의 동작이다. 이 테스트가 실패하면 docs/CATALOG.md 2절 schemaVersion 행을 함께 고친다.
  @Test(
    "정수가 되는 숫자 schemaVersion 은 그 정수로 읽는다",
    arguments: ["1.0", "1e0", "1E0", "10e-1", "1.00", "0.99999999999999999", "1.0000000000000001"]
  )
  func schemaVersionIntegralNumber(value: String) throws {
    let catalog = try BuildCatalog(jsonData: Data(#"{"schemaVersion":\#(value),"apps":[]}"#.utf8))

    #expect(catalog.apps.isEmpty)
  }
}

extension BuildCatalogTests {
  /// `createdAtAccepted` 의 입력과 기대 정수 밀리초.
  static let acceptedDates: [AcceptedDate] = [
    AcceptedDate(raw: "2026-10-21T04:08:49Z", milliseconds: Self.baseMilliseconds),
    AcceptedDate(raw: "2026-10-21T04:08:49.073Z", milliseconds: Self.baseMilliseconds + 73),
    AcceptedDate(raw: "2026-10-21T04:08:49.1Z", milliseconds: Self.baseMilliseconds + 100),
    AcceptedDate(raw: "2026-10-21T04:08:49.123456789Z", milliseconds: Self.baseMilliseconds + 123),
    AcceptedDate(raw: "2026-10-21T13:08:49+09:00", milliseconds: Self.baseMilliseconds),
    AcceptedDate(raw: "2026-10-21T13:08:49.073+09:00", milliseconds: Self.baseMilliseconds + 73),
    // 04:08:49 에 -03:30 이면 UTC 07:38:49.
    AcceptedDate(raw: "2026-10-21T04:08:49-03:30", milliseconds: Self.baseMilliseconds + 12_600_000),
    // 외부 도구가 낸 그대로: date -u +%Y-%m-%dT%H:%M:%SZ, git log -1 --format=%cI, GitHub API pushed_at.
    AcceptedDate(raw: "2026-10-21T12:16:06Z", milliseconds: Self.baseMilliseconds + 29_237_000),
    AcceptedDate(raw: "2026-10-21T19:01:21+09:00", milliseconds: Self.baseMilliseconds + 21_152_000),
    AcceptedDate(raw: "2026-10-21T10:01:25Z", milliseconds: Self.baseMilliseconds + 21_156_000),
    // 윤년 2월 29일과 달의 마지막 날.
    AcceptedDate(raw: "2000-02-29T00:00:00Z", milliseconds: 951_782_400_000),
    AcceptedDate(raw: "2024-02-29T00:00:00Z", milliseconds: 1_709_164_800_000),
    AcceptedDate(raw: "2400-02-29T00:00:00Z", milliseconds: 13_574_563_200_000),
    AcceptedDate(raw: "2026-02-28T00:00:00Z", milliseconds: 1_772_236_800_000),
    AcceptedDate(raw: "2026-04-30T00:00:00Z", milliseconds: 1_777_507_200_000),
    AcceptedDate(raw: "2026-12-31T00:00:00Z", milliseconds: 1_798_675_200_000),
    AcceptedDate(raw: "2026-01-31T00:00:00Z", milliseconds: 1_769_817_600_000),
    AcceptedDate(raw: "2026-03-31T00:00:00Z", milliseconds: 1_774_915_200_000),
    AcceptedDate(raw: "2026-05-31T00:00:00Z", milliseconds: 1_780_185_600_000),
    AcceptedDate(raw: "2026-07-31T00:00:00Z", milliseconds: 1_785_456_000_000),
    AcceptedDate(raw: "2026-08-31T00:00:00Z", milliseconds: 1_788_134_400_000),
    AcceptedDate(raw: "2026-10-31T00:00:00Z", milliseconds: 1_793_404_800_000),
    AcceptedDate(raw: "2026-06-30T00:00:00Z", milliseconds: 1_782_777_600_000),
    AcceptedDate(raw: "2026-09-30T00:00:00Z", milliseconds: 1_790_726_400_000),
    AcceptedDate(raw: "2026-11-30T00:00:00Z", milliseconds: 1_795_996_800_000),
    // 시·분·초와 시간대의 끝.
    AcceptedDate(raw: "2026-10-21T23:59:59Z", milliseconds: 1_792_627_199_000),
    AcceptedDate(raw: "2026-10-21T04:08:49+18:00", milliseconds: 1_792_490_929_000),
    AcceptedDate(raw: "2026-10-21T04:08:49-18:00", milliseconds: 1_792_620_529_000),
    AcceptedDate(raw: "2026-10-21T04:08:49-00:00", milliseconds: Self.baseMilliseconds),
    AcceptedDate(raw: "2026-10-21T04:08:49+17:59", milliseconds: 1_792_490_989_000),
    AcceptedDate(raw: "2026-10-21T04:08:49+00:59", milliseconds: 1_792_552_189_000),
    AcceptedDate(raw: "2026-10-21T04:08:49-17:59", milliseconds: 1_792_620_469_000),
    // 연도의 끝.
    AcceptedDate(raw: "1583-01-01T00:00:00Z", milliseconds: -12_212_553_600_000),
    AcceptedDate(raw: "9999-12-31T23:59:59Z", milliseconds: 253_402_300_799_000),
    AcceptedDate(raw: "1583-01-01T00:00:00+18:00", milliseconds: -12_212_618_400_000),
    AcceptedDate(raw: "9999-12-31T23:59:59-18:00", milliseconds: 253_402_365_599_000),
  ]
}
