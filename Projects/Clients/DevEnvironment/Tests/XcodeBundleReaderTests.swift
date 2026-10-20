import Core
import Foundation
import Testing
@testable import DevEnvironmentImpl

struct XcodeBundleReaderTests {
  private static let bundle = URL(filePath: "/Applications/Xcode.app", directoryHint: .isDirectory)

  private static func plist(
    _ values: [String: String],
    format: PropertyListSerialization.PropertyListFormat = .xml
  ) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: values, format: format, options: 0)
  }

  @Test(
    "XML·바이너리 Info.plist 의 Xcode 식별자·버전을 읽는다",
    arguments: [PropertyListSerialization.PropertyListFormat.xml, .binary]
  )
  func readsXcode(format: PropertyListSerialization.PropertyListFormat) throws {
    let data = try Self.plist(
      ["CFBundleIdentifier": "com.apple.dt.Xcode", "CFBundleShortVersionString": "27.1"],
      format: format
    )
    let installation = XcodeBundleReader.installation(bundleURL: Self.bundle, infoPlist: data)
    #expect(installation == XcodeInstallation(bundleURL: Self.bundle, version: OSVersion(major: 27, minor: 1)))
  }

  @Test(
    "식별자가 다르거나 버전이 없거나 형식이 틀리면 nil",
    arguments: [
      ["CFBundleIdentifier": "com.example.app", "CFBundleShortVersionString": "27.1"],
      ["CFBundleIdentifier": "com.apple.dt.Xcode"],
      ["CFBundleIdentifier": "com.apple.dt.Xcode", "CFBundleShortVersionString": "27.1 beta"],
      ["CFBundleShortVersionString": "27.1"],
    ]
  )
  func rejects(values: [String: String]) throws {
    #expect(try XcodeBundleReader.installation(bundleURL: Self.bundle, infoPlist: Self.plist(values)) == nil)
  }

  @Test("사전이 아니거나 plist 가 아니면 nil")
  func notDictionary() throws {
    let array = try PropertyListSerialization.data(fromPropertyList: ["com.apple.dt.Xcode"], format: .xml, options: 0)
    #expect(XcodeBundleReader.installation(bundleURL: Self.bundle, infoPlist: array) == nil)
    #expect(XcodeBundleReader.installation(bundleURL: Self.bundle, infoPlist: Data("oops".utf8)) == nil)
  }

  @Test("후보는 확장자가 .app(대소문자 무시)인 항목, 순서 유지")
  func candidates() {
    let entries = ["Xcode.app", "Notes.txt", "Xcode-beta.APP", "Utilities", "app"].map {
      URL(filePath: "/Applications/\($0)")
    }
    #expect(XcodeBundleReader.candidates(entries).map(\.lastPathComponent) == ["Xcode.app", "Xcode-beta.APP"])
  }

  @Test("같은 경로는 먼저 나온 하나만 남긴다")
  func unique() {
    let first = XcodeInstallation(bundleURL: Self.bundle, version: OSVersion(major: 27, minor: 1))
    let other = XcodeInstallation(
      bundleURL: URL(filePath: "/Applications/Xcode-beta.app", directoryHint: .isDirectory),
      version: OSVersion(major: 27, minor: 2)
    )
    #expect(XcodeBundleReader.unique([first, other, first]) == [first, other])
  }

  @Test("SDKSettings 의 Version 을 OS 버전으로 읽는다", arguments: [PropertyListSerialization.PropertyListFormat.xml, .binary])
  func sdkVersion(format: PropertyListSerialization.PropertyListFormat) throws {
    let data = try Self.plist(["Version": "27.1", "CanonicalName": "iphonesimulator27.1"], format: format)
    #expect(XcodeBundleReader.sdkVersion(settings: data) == OSVersion(major: 27, minor: 1))
  }

  @Test("SDKSettings 의 Version 이 없거나 형식이 틀리거나 plist 가 아니면 nil")
  func sdkVersionInvalid() throws {
    #expect(try XcodeBundleReader.sdkVersion(settings: Self.plist(["CanonicalName": "iphonesimulator27.1"])) == nil)
    #expect(try XcodeBundleReader.sdkVersion(settings: Self.plist(["Version": "27.x"])) == nil)
    #expect(XcodeBundleReader.sdkVersion(settings: Data("oops".utf8)) == nil)
  }

  @Test("SystemVersion 의 ProductBuildVersion 을 읽고, 없거나 비었으면 nil")
  func sdkBuild() throws {
    #expect(try XcodeBundleReader
      .sdkBuild(systemVersion: Self.plist(["ProductBuildVersion": "24A94232"])) == "24A94232")
    #expect(try XcodeBundleReader.sdkBuild(systemVersion: Self.plist(["ProductBuildVersion": ""])) == nil)
    #expect(try XcodeBundleReader.sdkBuild(systemVersion: Self.plist(["ProductVersion": "27.1"])) == nil)
    #expect(XcodeBundleReader.sdkBuild(systemVersion: Data("oops".utf8)) == nil)
  }
}
