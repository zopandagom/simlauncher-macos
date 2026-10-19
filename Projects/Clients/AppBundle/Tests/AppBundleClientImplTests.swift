import AppBundleInterface
import CommandTesting
import Core
import Foundation
import Testing
@testable import AppBundleImpl

/// 임시 폴더에 번들을 만들어 검사한다. 테스트마다 폴더를 지운다.
struct AppBundleClientImplTests {
  private let client = AppBundleClientImpl(hostArchitecture: .arm64, command: CommandClientFake.unused)

  @Test("정상 .app 의 정보를 읽고 location 은 표준화한 실제 경로다")
  func readsValidApp() async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let app = try directory.makeApp()

    let info = try await self.client.inspect(app.appending(path: "."))

    #expect(try info == AppBundleInfo(
      bundleID: #require(AppBundleID("com.example.sample")),
      displayName: "샘플 앱",
      version: "1.2",
      build: "34",
      platforms: [.iOSSimulator],
      architectures: [.arm64],
      minimumOSVersion: OSVersion(major: 17),
      location: info.location
    ))
    #expect(Self.path(info.location) == Self.path(app))
    #expect(info.location.isFileURL)
  }

  @Test("바이너리 plist 도 같은 정보로 읽고, 표시 이름이 없으면 파일 이름을 쓴다")
  func binaryPlistAndFileNameFallback() async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    var plist = TemporaryDirectory.simulatorPlist
    plist["CFBundleDisplayName"] = nil
    plist["CFBundleName"] = nil
    let app = try directory.makeApp("내 앱.app", plist: plist, format: .binary, executable: MachOBytes.thinX86)

    let info = try await self.client.inspect(app)

    #expect(info.displayName == "내 앱")
    #expect(info.bundleID.rawValue == "com.example.sample")
    #expect(info.architectures == [.x86_64])
  }

  @Test(".app 을 가리키는 심볼릭 링크는 따라가고 location 은 링크를 푼 실제 경로다")
  func followsSymlink() async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let app = try directory.makeApp()
    let link = directory.url.appending(path: "Link.app")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: app)

    let info = try await self.client.inspect(link)

    #expect(Self.path(info.location) == Self.path(app))
  }

  @Test("파일 URL 이 아니면 notLocalFile")
  func notLocalFile() async throws {
    await #expect(throws: AppBundleError.notLocalFile) {
      try await self.client.inspect(#require(URL(string: "https://example.com/Sample.app")))
    }
  }

  @Test("없는 경로는 fileNotFound")
  func fileNotFound() async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }

    await #expect(throws: AppBundleError.fileNotFound) {
      try await self.client.inspect(directory.url.appending(path: "None.app"))
    }
  }

  @Test(".ipa 파일은 대소문자와 상관없이 ipaFile", arguments: ["App.ipa", "App.IPA"])
  func ipaFile(name: String) async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let file = try directory.makeFile(name)

    await #expect(throws: AppBundleError.ipaFile) {
      try await self.client.inspect(file)
    }
  }

  @Test(".zip·확장자 없는 폴더·파일인 X.app 은 notAppBundle")
  func notAppBundle() async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let zip = try directory.makeFile("App.zip")
    let folder = directory.url.appending(path: "Folder", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let fileApp = try directory.makeFile("File.app")

    for url in [zip, folder, fileApp] {
      await #expect(throws: AppBundleError.notAppBundle) {
        try await self.client.inspect(url)
      }
    }
  }

  @Test("Info.plist 없이 Contents/Info.plist 만 있으면 macOSApp")
  func macOSApp() async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let app = try directory.makeApp("Mac.app", plist: nil)
    let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: TemporaryDirectory.simulatorPlist, format: .xml, options: 0)
      .write(to: contents.appending(path: "Info.plist"))

    await #expect(throws: AppBundleError.macOSApp) {
      try await self.client.inspect(app)
    }
  }

  @Test("Info.plist 가 없으면 invalidBundle")
  func missingInfoPlist() async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let app = try directory.makeApp(plist: nil)

    await #expect(throws: AppBundleError.invalidBundle) {
      try await self.client.inspect(app)
    }
  }

  @Test("Info.plist 가 FIFO 거나 1 MB 를 넘으면 읽다가 멈추지 않고 invalidBundle")
  func infoPlistNotRegularOrTooLarge() async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let fifoApp = try directory.makeApp("FIFO.app")
    try directory.makeFIFO(at: fifoApp.appending(path: "Info.plist"))
    let largeApp = try directory.makeApp("Large.app")
    var plist = TemporaryDirectory.simulatorPlist
    plist["Padding"] = String(repeating: "a", count: AppBundleClientImpl.infoPlistSizeLimit)
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
      .write(to: largeApp.appending(path: "Info.plist"))

    for app in [fifoApp, largeApp] {
      await #expect(throws: AppBundleError.invalidBundle) {
        try await self.client.inspect(app)
      }
    }
  }

  @Test("실행 파일이 없거나 FIFO 거나 Mach-O 가 아니면 invalidBundle")
  func invalidExecutable() async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let missing = try directory.makeApp("Missing.app", executable: nil)
    let fifo = try directory.makeApp("FIFO.app", executable: nil)
    try directory.makeFIFO(at: fifo.appending(path: "Sample"))
    let script = try directory.makeApp("Script.app", executable: Array("#!/bin/sh\necho hi\n".utf8))

    for app in [missing, fifo, script] {
      await #expect(throws: AppBundleError.invalidBundle) {
        try await self.client.inspect(app)
      }
    }
  }

  @Test("hostArchitecture 는 주입한 값이고, 기본 init 은 이 Mac 의 값을 쓴다")
  func hostArchitecture() {
    #expect(AppBundleClientImpl(hostArchitecture: .x86_64, command: CommandClientFake.unused)
      .hostArchitecture == .x86_64)
    #expect(AppBundleClientImpl(command: CommandClientFake.unused).hostArchitecture == HostArchitecture.current())
  }

  /// 끝의 `/` 를 뺀 경로 (디렉터리 표시 여부와 상관없이 비교한다).
  private static func path(_ url: URL) -> String {
    let path = url.path(percentEncoded: false)
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
  }
}
