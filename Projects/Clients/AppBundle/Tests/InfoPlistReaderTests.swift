import AppBundleInterface
import Core
import Foundation
import Testing
@testable import AppBundleImpl

struct InfoPlistReaderTests {
  @Test("XML 과 바이너리 plist 를 같은 값으로 읽는다", arguments: [PropertyListSerialization.PropertyListFormat.xml, .binary])
  func readsFormats(format: PropertyListSerialization.PropertyListFormat) throws {
    let fields = try InfoPlistReader.fields(from: Self.data(TemporaryDirectory.simulatorPlist, format: format))

    #expect(try fields == InfoPlistFields(
      bundleID: #require(AppBundleID("com.example.sample")),
      executableName: "Sample",
      displayName: "샘플 앱",
      version: "1.2",
      build: "34",
      platforms: [.iOSSimulator],
      minimumOSVersion: OSVersion(major: 17)
    ))
  }

  @Test("표시 이름은 CFBundleDisplayName → CFBundleName 순서이고, 둘 다 없거나 비었으면 nil")
  func displayName() throws {
    #expect(try Self.fields(removing: ["CFBundleDisplayName"]).displayName == "Sample")
    #expect(try Self.fields(setting: ["CFBundleDisplayName": " "]).displayName == "Sample")
    #expect(try Self.fields(removing: ["CFBundleDisplayName", "CFBundleName"]).displayName == nil)
  }

  @Test("버전·빌드·최소 OS·지원 플랫폼이 없으면 nil")
  func optionalFields() throws {
    let fields = try Self.fields(removing: [
      "CFBundleShortVersionString", "CFBundleVersion", "MinimumOSVersion", "CFBundleSupportedPlatforms",
    ])
    #expect(fields.version == nil)
    #expect(fields.build == nil)
    #expect(fields.minimumOSVersion == nil)
    #expect(fields.platforms == nil)
  }

  @Test("최소 OS 는 OSVersion 으로 읽고, 읽지 못하면 nil")
  func minimumOSVersion() throws {
    #expect(try Self.fields(setting: ["MinimumOSVersion": "26.0.1"]).minimumOSVersion == OSVersion(major: 26, patch: 1))
    #expect(try Self.fields(setting: ["MinimumOSVersion": "abc"]).minimumOSVersion == nil)
    #expect(try Self.fields(setting: ["MinimumOSVersion": 17]).minimumOSVersion == nil)
  }

  @Test("지원 플랫폼을 매핑하고, 문자열 배열이 아니면 빈 집합")
  func platforms() throws {
    #expect(
      try Self.fields(setting: ["CFBundleSupportedPlatforms": ["iPhoneOS", "iPhoneSimulator", "MacOSX"]]).platforms
        == [.iOS, .iOSSimulator, .other]
    )
    #expect(try Self.fields(setting: ["CFBundleSupportedPlatforms": []]).platforms == [])
    #expect(try Self.fields(setting: ["CFBundleSupportedPlatforms": "iPhoneSimulator"]).platforms == [])
  }

  @Test(
    "번들 ID 가 없거나 형식이 아니면 invalidBundle",
    arguments: [nil, "-x", "a b", "--stdout=/tmp/x"] as [String?]
  )
  func invalidBundleID(bundleID: String?) {
    var plist = TemporaryDirectory.simulatorPlist
    plist["CFBundleIdentifier"] = bundleID
    #expect(throws: AppBundleError.invalidBundle) {
      try InfoPlistReader.fields(from: Self.data(plist))
    }
  }

  @Test(
    "실행 파일 이름이 없거나 비었거나 `/` 를 포함하거나 정확히 `.`·`..` 면 invalidBundle",
    arguments: [nil, "", "a/b", "..", "../Sample", "/bin/sh", "."] as [String?]
  )
  func invalidExecutable(executable: String?) {
    var plist = TemporaryDirectory.simulatorPlist
    plist["CFBundleExecutable"] = executable
    #expect(throws: AppBundleError.invalidBundle) {
      try InfoPlistReader.fields(from: Self.data(plist))
    }
  }

  @Test("점이 들어간 실행 파일 이름은 그 이름 그대로 받는다", arguments: ["A..B", "App..Beta", ".hidden"])
  func dottedExecutable(executable: String) throws {
    #expect(try Self.fields(setting: ["CFBundleExecutable": executable]).executableName == executable)
  }

  @Test("사전이 아닌 plist 나 깨진 데이터는 invalidBundle")
  func notDictionary() throws {
    let array = try PropertyListSerialization.data(fromPropertyList: ["a"], format: .xml, options: 0)
    #expect(throws: AppBundleError.invalidBundle) { try InfoPlistReader.fields(from: array) }
    #expect(throws: AppBundleError.invalidBundle) { try InfoPlistReader.fields(from: Data("<plist".utf8)) }
    #expect(throws: AppBundleError.invalidBundle) { try InfoPlistReader.fields(from: Data()) }
  }

  private static func data(
    _ plist: [String: Any],
    format: PropertyListSerialization.PropertyListFormat = .xml
  ) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0)
  }

  private static func fields(
    setting values: [String: Any] = [:],
    removing keys: [String] = []
  ) throws -> InfoPlistFields {
    var plist = TemporaryDirectory.simulatorPlist.merging(values) { $1 }
    for key in keys {
      plist[key] = nil
    }
    return try InfoPlistReader.fields(from: Self.data(plist))
  }
}
