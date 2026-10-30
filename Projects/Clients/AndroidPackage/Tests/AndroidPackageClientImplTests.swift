import AndroidPackageInterface
import CommandInterface
import CommandTesting
import Core
import Foundation
import Synchronization
import Testing
@testable import AndroidPackageImpl

/// `inspect(_:)`. 실제 zipinfo·unzip 대신 CommandClientFake 가 출력을 돌려주고, 서명 블록은 테스트가 만든 파일 끝을 읽는다.
struct AndroidPackageClientImplTests {
  private final class LinkTargets: Sendable {
    let values = Mutex<[String?]>([])
  }

  /// 테스트마다 만드는 tmp·apk 와 Impl.
  private struct Harness {
    let directory: TemporaryDirectory
    let tmp: URL
    let command: CommandClientFake
    let client: AndroidPackageClientImpl
    /// 명령을 받을 때 본 링크 대상 (링크가 없으면 nil).
    let linkTargets: LinkTargets

    init(
      zipinfo: CommandResult = .success(Data(ZipinfoOutput.signed.utf8)),
      unzip: CommandResult = .success(AXMLTestBuilder.manifest(package: "com.example.app", minSDK: .int(26)).build())
    ) throws {
      self.directory = try TemporaryDirectory()
      self.tmp = try self.directory.makeDirectory("tmp")
      let linkTargets = LinkTargets()
      self.linkTargets = linkTargets
      self.command = CommandClientFake { invocation throws(CommandError) in
        let source = invocation.arguments.first { $0.hasSuffix("/" + InspectionFolder.linkName) }
        let target = source.flatMap { try? FileManager.default.destinationOfSymbolicLink(atPath: $0) }
        linkTargets.values.withLock { $0.append(target) }
        switch invocation.executable {
        case APKCommand.zipinfo: return zipinfo
        case APKCommand.unzip: return unzip
        default:
          Issue.record("모르는 명령: \(invocation.executable)")
          throw .launchFailed
        }
      }
      self.client = AndroidPackageClientImpl(command: self.command, temporaryDirectory: self.tmp)
    }

    /// tmp 에 남은 항목 이름.
    var leftovers: [String] {
      (try? FileManager.default.contentsOfDirectory(atPath: self.tmp.path(percentEncoded: false))) ?? []
    }

    var executables: [URL] {
      self.command.invocations.map(\.executable)
    }

    func error(_ url: URL) async -> AndroidPackageError? {
      do throws(AndroidPackageError) {
        _ = try await self.client.inspect(url)
        return nil
      } catch {
        return error
      }
    }
  }

  @Test("성공: zipinfo → unzip 순서, 인자·빈 환경·링크 대상, 결과 값, 끝나면 임시 폴더 없음")
  func success() async throws {
    let harness = try Harness(zipinfo: .success(Data(ZipinfoOutput.listing([
      ZipinfoOutput.line("AndroidManifest.xml"),
      ZipinfoOutput.line("lib/arm64-v8a/libx.so"),
      ZipinfoOutput.line("META-INF/CERT.RSA"),
    ]).utf8)))
    defer { harness.directory.remove() }
    let apk = try harness.directory.makeFile("My App [1].APK")

    let info = try await harness.client.inspect(apk)

    #expect(info.location.path(percentEncoded: false) == apk.path(percentEncoded: false))
    #expect(info.packageName.rawValue == "com.example.app")
    #expect(info.minSDK == .level(26))
    #expect(info.nativeABIs == ["arm64-v8a"])
    let invocations = harness.command.invocations
    #expect(invocations.map(\.executable) == [APKCommand.zipinfo, APKCommand.unzip])
    #expect(invocations.map(\.environment) == [[:], [:]])
    let link = try #require(invocations.first?.arguments.last)
    #expect(invocations[0].arguments == ["-s", "-T", link])
    #expect(invocations[1].arguments == ["-p", link, "AndroidManifest.xml"])
    let folder = URL(filePath: link).deletingLastPathComponent()
    #expect(folder.deletingLastPathComponent().path(percentEncoded: false) == harness.tmp.path(percentEncoded: false))
    #expect(folder.lastPathComponent.hasPrefix("SimLauncher-APK-"))
    #expect(harness.linkTargets.values.withLock { $0 } == [
      apk.path(percentEncoded: false),
      apk.path(percentEncoded: false),
    ])
    #expect(harness.leftovers.isEmpty)
  }

  @Test("링크를 거친 URL 은 실제 경로로 검사하고 location 에 담는다")
  func symlinkedURL() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    let apk = try harness.directory.makeFile("real.apk")
    let alias = harness.directory.url.appending(path: "alias.apk")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: apk)

    let info = try await harness.client.inspect(alias)

    #expect(info.location.path(percentEncoded: false) == apk.path(percentEncoded: false))
  }

  @Test(
    "확장자로 먼저 거절하고 명령을 부르지 않는다",
    arguments: [
      ("a.aab", AndroidPackageError.appBundle),
      ("a.AAB", .appBundle),
      ("a.apks", .splitPackage),
      ("a.xapk", .splitPackage),
      ("a.apkm", .splitPackage),
      ("a.ipa", .notAPK),
      ("a.zip", .notAPK),
      ("apk", .notAPK),
    ]
  )
  func extensions(name: String, expected: AndroidPackageError) async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let client = AndroidPackageClientImpl(command: CommandClientFake.unused, temporaryDirectory: directory.url)

    let file = try directory.makeFile(name)

    await #expect(throws: expected) { try await client.inspect(file) }
  }

  @Test("폴더는 확장자가 .apk 여도 notAPK")
  func folder() async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let client = AndroidPackageClientImpl(command: CommandClientFake.unused, temporaryDirectory: directory.url)

    let folder = try directory.makeDirectory("Folder.apk")

    await #expect(throws: AndroidPackageError.notAPK) { try await client.inspect(folder) }
  }

  @Test("파일 URL 이 아니면 notLocalFile, 없는 파일·대상 없는 링크는 fileNotFound")
  func locations() async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let client = AndroidPackageClientImpl(command: CommandClientFake.unused, temporaryDirectory: directory.url)
    let dangling = directory.url.appending(path: "dangling.apk")
    try FileManager.default.createSymbolicLink(
      atPath: dangling.path(percentEncoded: false),
      withDestinationPath: "/nonexistent/x.apk"
    )

    await #expect(throws: AndroidPackageError.notLocalFile) {
      try await client.inspect(#require(URL(string: "https://example.com/a.apk")))
    }
    await #expect(throws: AndroidPackageError.fileNotFound) {
      try await client.inspect(directory.url.appending(path: "none.apk"))
    }
    await #expect(throws: AndroidPackageError.fileNotFound) { try await client.inspect(dangling) }
  }

  @Test("zipinfo 종료 코드 9(잘림·zip 아님)·출력 해석 실패는 unreadable 이고 unzip 을 부르지 않는다")
  func zipinfoFailures() async throws {
    for zipinfo in [
      CommandResult.failure(9, "End-of-central-directory signature not found."),
      .success(Data("garbage".utf8)),
    ] {
      let harness = try Harness(zipinfo: zipinfo)
      defer { harness.directory.remove() }
      let apk = try harness.directory.makeFile("a.apk")

      #expect(await harness.error(apk) == .unreadable)
      #expect(harness.executables == [APKCommand.zipinfo])
      #expect(harness.leftovers.isEmpty)
    }
  }

  @Test("목록 검사 실패(링크·App Bundle)는 그 에러이고 임시 폴더를 지운다")
  func listingCheckFailures() async throws {
    let cases: [(String, AndroidPackageError)] = [
      (
        ZipinfoOutput.listing([
          ZipinfoOutput.line("AndroidManifest.xml"),
          ZipinfoOutput.line("x", permissions: "lrwxr-xr-x"),
        ]),
        .unsafeEntry
      ),
      (ZipinfoOutput.listing([ZipinfoOutput.line("base/manifest/AndroidManifest.xml")]), .appBundle),
    ]
    for (output, expected) in cases {
      let harness = try Harness(zipinfo: .success(Data(output.utf8)))
      defer { harness.directory.remove() }
      let apk = try harness.directory.makeFile("a.apk")

      #expect(await harness.error(apk) == expected)
      #expect(harness.leftovers.isEmpty)
    }
  }

  @Test("v1 서명 파일도 v2+ 블록도 없으면 unsigned 이고 manifest 를 읽지 않는다")
  func unsigned() async throws {
    let harness = try Harness(zipinfo: .success(Data(ZipinfoOutput.withoutV1.utf8)))
    defer { harness.directory.remove() }
    let apk = try harness.directory.makeFile("a.apk", contents: Data(ZipTail.file(signed: false)))

    #expect(await harness.error(apk) == .unsigned)
    #expect(harness.executables == [APKCommand.zipinfo])
    #expect(harness.leftovers.isEmpty)
  }

  @Test("v1 이 없어도 v2+ 블록이 있거나 블록 유무를 모르면(EOCD 없음) 통과한다")
  func signingBlockOrUnknown() async throws {
    for contents in [ZipTail.file(signed: true), Array("not a zip".utf8)] {
      let harness = try Harness(zipinfo: .success(Data(ZipinfoOutput.withoutV1.utf8)))
      defer { harness.directory.remove() }
      let apk = try harness.directory.makeFile("a.apk", contents: Data(contents))

      #expect(try await harness.client.inspect(apk).packageName.rawValue == "com.example.app")
    }
  }

  @Test("unzip 종료 코드 11(항목 없음)·AXML 해석 실패·package 형식 위반은 unreadable")
  func manifestFailures() async throws {
    let cases: [CommandResult] = [
      .failure(11, "caution: filename not matched:  AndroidManifest.xml"),
      .success(Data("<manifest/>".utf8)),
      .success(AXMLTestBuilder.manifest(package: "not-a-package").build()),
      .success(Data(count: AXMLManifestReader.sizeLimit + 1)),
    ]
    for unzip in cases {
      let harness = try Harness(unzip: unzip)
      defer { harness.directory.remove() }
      let apk = try harness.directory.makeFile("a.apk")

      #expect(await harness.error(apk) == .unreadable)
      #expect(harness.leftovers.isEmpty)
    }
  }

  @Test("zipinfo 를 시작하지 못하면 inspectionUnavailable 이고 임시 폴더를 지운다")
  func launchFailed() async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let tmp = try directory.makeDirectory("tmp")
    let command = CommandClientFake { _ throws(CommandError) in throw .launchFailed }
    let client = AndroidPackageClientImpl(command: command, temporaryDirectory: tmp)
    let apk = try directory.makeFile("a.apk")

    await #expect(throws: AndroidPackageError.inspectionUnavailable) { try await client.inspect(apk) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.path(percentEncoded: false)).isEmpty)
  }

  @Test("임시 폴더를 만들 수 없으면 inspectionUnavailable 이고 명령을 부르지 않는다")
  func temporaryDirectoryMissing() async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let client = AndroidPackageClientImpl(
      command: CommandClientFake.unused,
      temporaryDirectory: directory.url.appending(path: "missing", directoryHint: .isDirectory)
    )
    let apk = try directory.makeFile("a.apk")

    await #expect(throws: AndroidPackageError.inspectionUnavailable) { try await client.inspect(apk) }
  }
}
