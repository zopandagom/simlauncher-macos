import CommandTesting
import Core
import Foundation
import Testing
@testable import DevEnvironmentImpl

/// Info.plist 읽기와 번들 표준 경로.
struct DevEnvironmentClientImplFileTests {
  private static let limit = DevEnvironmentClientImpl.infoPlistSizeLimit

  @Test("Info.plist 는 1 MB 까지 읽고 1 MB + 1 B 는 읽지 않는다")
  func sizeLimit() throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let exact = tmp.url.appending(path: "exact.plist")
    let over = tmp.url.appending(path: "over.plist")
    try Data(count: Self.limit).write(to: exact)
    try Data(count: Self.limit + 1).write(to: over)

    #expect(Self.limit == 1_048_576)
    #expect(DevEnvironmentClientImpl.readInfoPlist(exact)?.count == Self.limit)
    #expect(DevEnvironmentClientImpl.readInfoPlist(over) == nil)
  }

  @Test("상한을 넘는 Info.plist 의 번들은 Xcode 로 보지 않는다")
  func oversizedBundleIsSkipped() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let bundle = try tmp.makeXcode()
    try Data(count: Self.limit + 1).write(to: bundle.appending(path: "Contents/Info.plist"))
    let command = Responder.command(select: .exit(2))

    let client = DevEnvironmentClientImpl(command: command, applicationsDirectory: tmp.applications)
    #expect(await client.selectedXcode() == nil)
  }

  @Test("Contents/Info.plist 가 폴더거나 대상 없는 링크면 그 번들은 고르지 않는다", arguments: [false, true])
  func infoPlistNotRegularFile(danglingLink: Bool) async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let bundle = try tmp.makeXcode(infoPlist: false)
    let plist = bundle.appending(path: "Contents/Info.plist")
    if danglingLink {
      try tmp.link("Info.plist", in: bundle.appending(path: "Contents"), to: tmp.url.appending(path: "missing.plist"))
    } else {
      try FileManager.default.createDirectory(at: plist, withIntermediateDirectories: false)
    }
    let command = Responder.command(select: .exit(2))

    #expect(DevEnvironmentClientImpl.readInfoPlist(plist) == nil)
    let client = DevEnvironmentClientImpl(command: command, applicationsDirectory: tmp.applications)
    #expect(await client.selectedXcode() == nil)
  }

  @Test("번들 안의 다른 일반 파일을 가리키는 Info.plist 링크는 따라가 읽는다")
  func infoPlistLinkIsFollowed() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let source = try tmp.makeXcode("Source.app", in: tmp.elsewhere)
    let bundle = try tmp.makeXcode(infoPlist: false)
    let contents = bundle.appending(path: "Contents")
    try FileManager.default.copyItem(
      at: source.appending(path: "Contents/Info.plist"),
      to: contents.appending(path: "Real-Info.plist")
    )
    try tmp.link("Info.plist", in: contents, to: contents.appending(path: "Real-Info.plist"))
    let command = Responder.command(select: .exit(2))

    let client = DevEnvironmentClientImpl(command: command, applicationsDirectory: tmp.applications)
    #expect(try await client.selectedXcode() == tmp.installation(bundle, 27, 1))
  }

  @Test("링크 경로와 실제 경로로 만든 같은 번들은 같은 값이다")
  func canonicalSameBundle() throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let real = try tmp.makeXcode("Xcode-27.1.app")
    let link = try tmp.link("Xcode.app", to: real)
    let version = OSVersion(major: 27, minor: 1)

    let viaLink = try XcodeInstallation(
      bundleURL: #require(DevEnvironmentClientImpl.canonicalBundleURL(link)),
      version: version
    )
    let viaReal = try XcodeInstallation(
      bundleURL: #require(DevEnvironmentClientImpl.canonicalBundleURL(real)),
      version: version
    )

    #expect(viaLink == viaReal)
    #expect(Set([viaLink, viaReal]).count == 1)
  }

  @Test("표준 경로는 realpath 라 /private 를 지우지 않는다")
  func canonicalKeepsPrivate() throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let viaTmp = DevEnvironmentClientImpl.canonicalBundleURL(URL(filePath: "/tmp", directoryHint: .isDirectory))
    let viaPrivate = DevEnvironmentClientImpl.canonicalBundleURL(URL(
      filePath: "/private/tmp",
      directoryHint: .isDirectory
    ))

    #expect(viaTmp?.path(percentEncoded: false) == "/private/tmp/")
    #expect(viaPrivate?.path(percentEncoded: false) == "/private/tmp/")
    let canonical = DevEnvironmentClientImpl.canonicalBundleURL(tmp.url)
    #expect(canonical?.path(percentEncoded: false) == RealPath.of(tmp.url).map { $0 + "/" })
    if tmp.url.path(percentEncoded: false).hasPrefix("/var/") {
      #expect(canonical?.path(percentEncoded: false).hasPrefix("/private/var/folders/") == true)
    }
  }

  @Test("대상이 없는 경로는 표준 경로가 없다")
  func canonicalMissing() throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    #expect(DevEnvironmentClientImpl.canonicalBundleURL(tmp.url.appending(path: "Missing.app")) == nil)
  }
}
