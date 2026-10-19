import AppBundleInterface
import CommandInterface
import CommandTesting
import Foundation
import Testing
@testable import AppBundleImpl

/// `extractApp(fromZip:)`·`removeExtracted(_:)`·`removeLeftoverExtractions()`. 실제 zipinfo·ditto 대신
/// CommandClientFake 가 zipinfo 출력을 돌려주고, ditto 자리에서 `contents/` 에 트리를 만든다.
struct AppBundleClientImplExtractTests {
  /// 테스트마다 만드는 tmp·zip 과 Impl.
  private struct Harness {
    let directory: TemporaryDirectory
    let tmp: URL
    let zip: URL
    let command: CommandClientFake
    let client: AppBundleClientImpl

    /// - Parameters:
    ///   - zipinfo: zipinfo 결과.
    ///   - ditto: ditto 자리에서 받은 `contents/` 에 트리를 만들고 결과를 돌려준다.
    ///   - capacity: 여유 공간 (nil 이면 읽지 못함).
    init(
      zipinfo: CommandResult = .success(Data(ZipinfoOutput.normal.utf8)),
      ditto: @escaping @Sendable (URL) throws -> CommandResult = { contents in
        try FileTree.app(contents)
        return .success()
      },
      capacity: Int64? = .max
    ) throws {
      self.directory = try TemporaryDirectory()
      self.tmp = self.directory.url.appending(path: "tmp", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: self.tmp, withIntermediateDirectories: false)
      self.zip = try self.directory.makeFile("Build.zip")
      self.command = CommandClientFake { invocation throws(CommandError) in
        switch invocation.executable {
        case ZipCommand.zipinfo:
          return zipinfo
        case ZipCommand.ditto:
          do {
            return try ditto(URL(filePath: invocation.arguments[3], directoryHint: .isDirectory))
          } catch {
            Issue.record("트리를 만들지 못했다: \(error)")
            throw .launchFailed
          }
        default:
          Issue.record("모르는 명령: \(invocation.executable)")
          throw .launchFailed
        }
      }
      self.client = AppBundleClientImpl(
        hostArchitecture: .arm64,
        command: self.command,
        temporaryDirectory: self.tmp,
        availableCapacity: { _ in capacity }
      )
    }

    /// tmp 에 남은 항목 이름.
    var leftovers: [String] {
      (try? FileManager.default.contentsOfDirectory(atPath: self.tmp.path(percentEncoded: false))) ?? []
    }

    var executables: [URL] {
      self.command.invocations.map(\.executable)
    }

    func extractError(_ url: URL? = nil) async -> AppBundleError? {
      do throws(AppBundleError) {
        _ = try await self.client.extractApp(fromZip: url ?? self.zip)
        return nil
      } catch {
        return error
      }
    }
  }

  @Test("성공: zipinfo → ditto 순서, 인자·빈 환경·source.zip 링크 대상, ExtractedApp, removeExtracted 뒤 폴더 없음")
  func success() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }

    let extracted = try await harness.client.extractApp(fromZip: harness.zip)

    let tmpReal = try #require(RealPath.of(harness.tmp))
    let folder = extracted.folder.path(percentEncoded: false)
    #expect(extracted.folder.deletingLastPathComponent().path(percentEncoded: false) == tmpReal + "/")
    #expect(extracted.folder.lastPathComponent.hasPrefix("SimLauncher-Unzip-"))
    #expect(extracted.app == URL(filePath: folder + "contents/Sample.app", directoryHint: .isDirectory))
    let source = folder + "source.zip"
    let contents = folder + "contents/"
    #expect(harness.command.invocations == [
      .init(executable: ZipCommand.zipinfo, arguments: ["-s", "-T", source], environment: [:]),
      .init(executable: ZipCommand.ditto, arguments: ["-x", "-k", source, contents], environment: [:]),
    ])
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: source) == RealPath.of(harness.zip))
    #expect(FileTree.exists(extracted.app.appending(path: "Info.plist")))

    await harness.client.removeExtracted(extracted)

    #expect(harness.leftovers.isEmpty)
  }

  @Test("zipinfo 결과로 거절하면 ditto 를 부르지 않고 폴더를 남기지 않는다")
  func listingFailures() async throws {
    let cases: [(CommandResult, AppBundleError)] = [
      (.failure(9, "End-of-central-directory signature not found."), .zipUnreadable),
      (CommandResult(exitCode: 1, stdout: Data(ZipinfoOutput.empty.utf8), stderr: Data()), .zipWithoutApp),
      (CommandResult(exitCode: 1, stdout: Data(ZipinfoOutput.prefixed.utf8), stderr: Data()), .zipUnreadable),
      (CommandResult(exitCode: 1, stdout: Data(ZipinfoOutput.normal.utf8), stderr: Data()), .zipUnreadable),
      (.success(Data("garbage".utf8)), .zipUnreadable),
      (
        .success(Data(ZipinfoOutput.single("-rw-r--r--  2.0 unx  1 b- defN 20240101.000000 ../x").utf8)),
        .zipUnsafeEntry
      ),
      (
        .success(Data(ZipinfoOutput.single("-rw-r--r--  2.0 unx  1 b- defN 20240101.000000 README").utf8)),
        .zipWithoutApp
      ),
    ]
    for (zipinfo, expected) in cases {
      let harness = try Harness(zipinfo: zipinfo)
      defer { harness.directory.remove() }

      #expect(await harness.extractError() == expected)
      #expect(harness.executables == [ZipCommand.zipinfo])
      #expect(harness.leftovers.isEmpty)
    }
  }

  @Test("선언 크기 합이 여유 공간보다 크면 ditto 를 부르지 않고 insufficientDiskSpace, 같으면 통과")
  func diskSpace() async throws {
    let over = try Harness(capacity: 291)
    defer { over.directory.remove() }
    #expect(await over.extractError() == .insufficientDiskSpace)
    #expect(over.executables == [ZipCommand.zipinfo])
    #expect(over.leftovers.isEmpty)

    let equal = try Harness(capacity: 292)
    defer { equal.directory.remove() }
    #expect(await equal.extractError() == nil)
    #expect(equal.executables == [ZipCommand.zipinfo, ZipCommand.ditto])
  }

  @Test("여유 공간을 읽지 못하면 확인을 건너뛰고 ditto 를 부른다")
  func unknownCapacity() async throws {
    let harness = try Harness(capacity: nil)
    defer { harness.directory.remove() }

    #expect(await harness.extractError() == nil)
    #expect(harness.executables == [ZipCommand.zipinfo, ZipCommand.ditto])
  }

  @Test("ditto 실패: No space left on device 면 insufficientDiskSpace, 그 밖은 zipUnreadable. 폴더를 남기지 않는다")
  func dittoFailures() async throws {
    let cases: [(String, AppBundleError)] = [
      ("ditto: /x/contents/Sample.app/big: No space left on device\n", .insufficientDiskSpace),
      ("ditto: Couldn't read pkzip signature.\n", .zipUnreadable),
      ("", .zipUnreadable),
    ]
    for (stderr, expected) in cases {
      let harness = try Harness(ditto: { contents in
        // 일부만 풀린 채 실패한 상태.
        try FileTree.file(contents, "Sample.app/partial")
        return .failure(1, stderr)
      })
      defer { harness.directory.remove() }

      #expect(await harness.extractError() == expected)
      #expect(harness.leftovers.isEmpty)
    }
  }

  @Test("ditto stderr 가 UTF-8 이 아니어도 Latin-1 로 읽어 디스크 부족을 찾는다")
  func dittoLatin1Stderr() async throws {
    let harness = try Harness(ditto: { _ in
      CommandResult(exitCode: 1, stdout: Data(), stderr: Data([0xFF]) + Data(" No space left on device".utf8))
    })
    defer { harness.directory.remove() }

    #expect(await harness.extractError() == .insufficientDiskSpace)
  }

  @Test("푼 뒤 검사 실패: 밖을 가리키는 링크·맨 위 .app 링크·.app 둘·없음, 읽을 수 없는 폴더. 폴더를 남기지 않는다")
  func treeFailures() async throws {
    let cases: [(@Sendable (URL) throws -> Void, AppBundleError)] = [
      ({ try FileTree.app($0); try FileTree.link($0, "Sample.app/escape", to: "/etc") }, .zipUnsafeEntry),
      (
        { try FileTree.app($0); try FileTree.link($0, "Sample.app/x", to: "y/.."); try FileTree.link(
          $0,
          "Sample.app/y",
          to: "."
        ) },
        .zipUnsafeEntry
      ),
      ({ try FileTree.app($0); try FileTree.link($0, "Sample.app/dangling", to: "nowhere") }, .zipUnsafeEntry),
      ({ try FileTree.link($0, "Sample.app", to: "/Applications/Safari.app") }, .zipUnsafeEntry),
      ({ try FileTree.app($0); try FileTree.app($0, "Other.app") }, .zipWithMultipleApps),
      ({ try FileTree.file($0, "README") }, .zipWithoutApp),
      ({ contents in
        try FileTree.app(contents)
        try FileTree.file(contents, "Sample.app/outer/inner/f")
        try FileTree.directory(contents, "Sample.app/outer/inner", mode: 0o555)
        try FileTree.directory(contents, "Sample.app/outer", mode: 0o111)
      }, .zipUnreadable),
    ]
    for (build, expected) in cases {
      let harness = try Harness(ditto: { contents in
        try build(contents)
        return .success()
      })
      defer { harness.directory.remove() }

      #expect(await harness.extractError() == expected)
      #expect(harness.leftovers.isEmpty)
    }
  }

  @Test("명령을 시작하지 못하면 extractionUnavailable 이고 폴더를 남기지 않는다")
  func launchFailed() async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let tmp = directory.url.appending(path: "tmp", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: false)
    let zip = try directory.makeFile("Build.zip")
    let client = AppBundleClientImpl(
      hostArchitecture: .arm64,
      command: CommandClientFake { _ throws(CommandError) in throw .launchFailed },
      temporaryDirectory: tmp,
      availableCapacity: { _ in .max }
    )

    await #expect(throws: AppBundleError.extractionUnavailable) { try await client.extractApp(fromZip: zip) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.path(percentEncoded: false)).isEmpty)
  }

  @Test("임시 폴더가 없으면 extractionUnavailable 이고 명령을 부르지 않는다")
  func missingTemporaryDirectory() async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let zip = try directory.makeFile("Build.zip")
    let client = AppBundleClientImpl(
      hostArchitecture: .arm64,
      command: CommandClientFake.unused,
      temporaryDirectory: directory.url.appending(path: "missing", directoryHint: .isDirectory),
      availableCapacity: { _ in .max }
    )

    await #expect(throws: AppBundleError.extractionUnavailable) { try await client.extractApp(fromZip: zip) }
  }

  @Test("파일 URL 이 아니면 notLocalFile, 없는 파일이면 fileNotFound, 폴더면 zipUnreadable. 명령을 부르지 않는다")
  func inputFailures() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    let missing = harness.directory.url.appending(path: "missing.zip")
    let folder = harness.directory.url.appending(path: "Folder.zip", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)

    #expect(await harness.extractError(URL(string: "https://example.com/Build.zip")) == .notLocalFile)
    #expect(await harness.extractError(missing) == .fileNotFound)
    #expect(await harness.extractError(folder) == .zipUnreadable)
    #expect(harness.command.invocations.isEmpty)
    #expect(harness.leftovers.isEmpty)
  }

  @Test("removeLeftoverExtractions 는 지금 쓰는 폴더를 건너뛰고 앞선 실행의 폴더를 지운다")
  func leftovers() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    let stale = harness.tmp.appending(path: "SimLauncher-Unzip-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileTree.file(stale, "contents/Sample.app/Info.plist")
    let extracted = try await harness.client.extractApp(fromZip: harness.zip)

    await harness.client.removeLeftoverExtractions()

    #expect(!FileTree.exists(stale))
    #expect(FileTree.exists(extracted.app))
    await harness.client.removeExtracted(extracted)
    #expect(harness.leftovers.isEmpty)
  }

  @Test("removeExtracted 는 이 Client 형식이 아닌 폴더를 지우지 않는다")
  func removeExtractedIgnoresForeignFolder() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    let foreign = harness.directory.url.appending(path: "Keep", directoryHint: .isDirectory)
    try FileTree.file(foreign, "contents/Sample.app/Info.plist")

    await harness.client.removeExtracted(ExtractedApp(
      app: foreign.appending(path: "contents/Sample.app"),
      folder: foreign
    ))

    #expect(FileTree.exists(foreign.appending(path: "contents/Sample.app/Info.plist")))
  }
}
