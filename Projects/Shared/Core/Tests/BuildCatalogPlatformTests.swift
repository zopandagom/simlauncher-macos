import Foundation
import Testing
@testable import Core

/// schemaVersion 2 의 앱 `platform` 과 플랫폼 거르기 (docs/CATALOG.md). v1 은 platform 을 읽지 않는다.
struct BuildCatalogPlatformTests {
  /// v2 앱 JSON. `platform` 은 JSON 값 그대로의 문자열이고 nil 이면 필드를 뺀다.
  static func app(id: String = "a", platform: String? = #""ios""#, replacing: [String: String] = [:]) -> String {
    var fields = replacing
    if let platform {
      fields["platform"] = platform
    }
    return CatalogText.app(id: id, replacing: fields)
  }

  static func catalog(_ apps: [String]) -> Data {
    CatalogText.catalog(apps, schemaVersion: 2)
  }

  @Test("v1 은 앱의 platform 을 어떤 값이든 무시하고 모두 iOS 로 본다", arguments: [#""android""#, #""iOS""#, "3", "null"])
  func schemaVersion1IgnoresPlatform(value: String) throws {
    let catalog = try BuildCatalog(jsonData: CatalogText.catalog([CatalogText.app(replacing: ["platform": value])]))

    #expect(catalog.schemaVersion == 1)
    #expect(catalog.apps.map(\.platform) == [.ios])
  }

  @Test("v1 은 같은 id 를 platform 과 관계없이 중복으로 거절한다")
  func schemaVersion1DuplicateIgnoresPlatform() {
    let apps = [
      CatalogText.app(id: "a", replacing: ["platform": #""ios""#]),
      CatalogText.app(id: "a", replacing: ["platform": #""android""#]),
    ]

    #expect(catalogProblem(CatalogText.catalog(apps)) == .duplicateAppID(position: catalogPosition(app: 1, "a")))
  }

  @Test("v2: 두 플랫폼을 파일 순서로 읽고, apps(for:)·app(_:for:) 가 플랫폼별로 거른다")
  func schemaVersion2ReadsPlatforms() throws {
    let apps = [
      Self.app(id: "one", platform: #""android""#),
      Self.app(id: "two", platform: #""ios""#),
      Self.app(id: "three", platform: #""android""#),
    ]

    let catalog = try BuildCatalog(jsonData: Self.catalog(apps))

    #expect(catalog.schemaVersion == 2)
    #expect(catalog.apps.map(\.id.rawValue) == ["one", "two", "three"])
    #expect(catalog.apps.map(\.platform) == [.android, .ios, .android])
    #expect(catalog.apps(for: .android).map(\.id.rawValue) == ["one", "three"])
    #expect(catalog.apps(for: .ios).map(\.id.rawValue) == ["two"])
    #expect(catalog.app(BuildCatalog.AppID("two"), for: .ios)?.name == "App two")
    #expect(catalog.app(BuildCatalog.AppID("two"), for: .android) == nil)
    #expect(catalog.app(BuildCatalog.AppID("Two"), for: .ios) == nil)
  }

  @Test("v2: platform 이 없거나 null 이면 missingField(.platform), 위치에 앱 id", arguments: [nil, "null"])
  func missingPlatform(value: String?) {
    let data = Self.catalog([Self.app(id: "a", platform: value)])

    #expect(catalogProblem(data) == .missingField(.platform, position: catalogPosition(app: 0, "a")))
  }

  @Test("v2: platform 이 문자열이 아니면 wrongType(.platform)", arguments: ["1", "true", "[]", #"{"a":1}"#])
  func platformWrongType(value: String) {
    let data = Self.catalog([Self.app(id: "a", platform: value)])

    #expect(catalogProblem(data) == .wrongType(.platform, position: catalogPosition(app: 0, "a")))
  }

  @Test(
    "v2: platform 은 소문자 정확히 일치만 받는다 (대문자·공백·빈 값·모르는 값은 unsupportedPlatform)",
    arguments: ["iOS", " ios", "ios ", "", "windows", "Android"]
  )
  func unsupportedPlatform(value: String) {
    let data = Self.catalog([Self.app(id: "a", platform: CatalogText.quoted(value))])

    #expect(catalogProblem(data) == .unsupportedPlatform(position: catalogPosition(app: 0, "a")))
  }

  @Test("v2 검사 순서: id 형식이 platform 보다 먼저, platform 이 id 중복·name 보다 먼저")
  func checkOrder() {
    let badIDFirst = Self.catalog([Self.app(id: "-bad", platform: #""iOS""#)])
    #expect(catalogProblem(badIDFirst) == .invalidID(position: catalogPosition(app: 0, nil)))

    let platformBeforeDuplicate = Self.catalog([Self.app(id: "a"), Self.app(id: "a", platform: #""iOS""#)])
    #expect(catalogProblem(platformBeforeDuplicate) == .unsupportedPlatform(position: catalogPosition(app: 1, "a")))

    let platformBeforeName = Self.catalog([Self.app(id: "a", platform: nil, replacing: ["name": "1"])])
    #expect(catalogProblem(platformBeforeName) == .missingField(.platform, position: catalogPosition(app: 0, "a")))
  }

  @Test("v2: 같은 id 라도 다른 platform 이면 통과, 같은 platform 이면 대소문자 무시로 중복 거절")
  func duplicateWithinPlatform() throws {
    let crossPlatform = Self.catalog([Self.app(id: "a"), Self.app(id: "a", platform: #""android""#)])
    let catalog = try BuildCatalog(jsonData: crossPlatform)
    #expect(catalog.apps.map(\.platform) == [.ios, .android])

    let samePlatform = Self.catalog([
      Self.app(id: "a", platform: #""android""#),
      Self.app(id: "b"),
      Self.app(id: "A", platform: #""android""#),
    ])
    #expect(catalogProblem(samePlatform) == .duplicateAppID(position: catalogPosition(app: 2, "A")))
  }

  @Test("v2 의 Android 앱 buildURL 은 확장자를 보지 않고 DownloadURL 규칙만 본다")
  func androidBuildURLExtensionNotChecked() throws {
    let version = CatalogText.version(id: "v1", replacing: ["buildURL": #""https://example.com/download?id=1""#])
    let app = Self.app(id: "a", platform: #""android""#, replacing: ["versions": "[\(version)]"])

    let catalog = try BuildCatalog(jsonData: Self.catalog([app]))

    #expect(catalog.apps.first?.versions.first?.buildURL.url.absoluteString == "https://example.com/download?id=1")

    let httpVersion = CatalogText.version(id: "v1", replacing: ["buildURL": #""http://example.com/a.apk""#])
    let httpApp = Self.app(id: "a", platform: #""android""#, replacing: ["versions": "[\(httpVersion)]"])
    #expect(
      catalogProblem(Self.catalog([httpApp]))
        == .invalidBuildURL(.notHTTPS, position: catalogPosition(app: 0, "a", version: 0, "v1"))
    )
  }

  @Test("BuildCatalog(apps:) 의 기본 schemaVersion 은 가장 새 규격, App 의 기본 platform 은 iOS")
  func defaults() {
    let app = BuildCatalog.App(id: BuildCatalog.AppID("a"), name: "A", versions: [])

    #expect(BuildCatalog(apps: [app]).schemaVersion == BuildCatalog.latestSchemaVersion)
    #expect(app.platform == .ios)
  }
}
