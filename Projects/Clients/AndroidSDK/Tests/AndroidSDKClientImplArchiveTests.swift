import AndroidSDKInterface
import CommandInterface
import CommandTesting
import Core
import DownloadInterface
import DownloadTesting
import Foundation
import Testing
@testable import AndroidSDKImpl

/// `install(_:acceptedLicenses:progress:)` 의 풀기·옮기기: zipinfo 목록 검사, 선언 크기, unzip 종료 코드, 푼 트리 검사, 최종 경로 이름 바꾸기.
struct AndroidSDKClientImplArchiveTests {
  @Test("zipinfo: 실패·읽지 못함 → archiveUnreadable, 모양이 틀린 목록 → archiveUnsafe, unzip 을 부르지 않고 스테이징 지움")
  func listingFailures() async throws {
    let cases: [(CommandResult, AndroidSDKInstallError)] = [
      (.failure(9, "End-of-central-directory signature not found."), .archiveUnreadable(.platformTools)),
      (
        CommandResult(exitCode: 1, stdout: Data(PackageSpec(.platformTools).zipinfo.utf8), stderr: Data()),
        .archiveUnreadable(.platformTools)
      ),
      (.success(Data("garbage".utf8)), .archiveUnreadable(.platformTools)),
      (
        .success(Data(ZipinfoText.listing(["-rw-r--r--  3.0 unx 1 bx defN 20251014.120000 ../x"]).utf8)),
        .archiveUnsafe(.platformTools)
      ),
      (.success(Data(ZipinfoText.listing([
        "-rw-r--r--  3.0 unx 1 bx defN 20251014.120000 platform-tools/adb",
        "-rw-r--r--  3.0 unx 1 bx defN 20251014.120000 other/x",
      ]).utf8)), .archiveUnsafe(.platformTools)),
    ]
    for (zipinfo, expected) in cases {
      let harness = try Harness(zipinfo: { _ in zipinfo })
      defer { harness.directory.remove() }

      #expect(try await harness.install(harness.plan([.platformTools])).result == .failure(expected))
      #expect(harness.executables == [PackageZipCommand.zipinfo])
      #expect(harness.stagingNames.isEmpty)
      #expect(harness.removedDownloads.count == 1)
    }
  }

  @Test("선언 크기 합이 SDK 볼륨 여유보다 크면 unzip 전에 insufficientDiskSpace (Zip64 크기 포함)")
  func declaredSizeOverCapacity() async throws {
    let declared = PackageSpec(.systemImage).declaredBytes
    let harness = try Harness(capacity: { url in
      url.path(percentEncoded: false).contains("/sdk") ? declared - 1 : .max
    })
    defer { harness.directory.remove() }
    try FileTree.directory(harness.sdk, "")

    let result = try await harness.install(harness.plan([.systemImage])).result

    #expect(result == .failure(.insufficientDiskSpace(.systemImage, required: declared, available: declared - 1)))
    #expect(harness.executables == [PackageZipCommand.zipinfo])
    #expect(harness.stagingNames.isEmpty)
  }

  @Test("unzip 종료 코드 50 → insufficientDiskSpace, 1·9 → archiveUnreadable, 둘 다 스테이징·받은 폴더 지움")
  func unzipExitCodes() async throws {
    let cases: [(Int32, AndroidSDKInstallError)] = [
      (50, .insufficientDiskSpace(.platformTools, required: 1060, available: .max)),
      (1, .archiveUnreadable(.platformTools)),
      (9, .archiveUnreadable(.platformTools)),
    ]
    for (code, expected) in cases {
      let harness = try Harness(unzip: { spec, contents in
        try spec.extract(into: contents)
        return .failure(code, "write error (disk full?)")
      })
      defer { harness.directory.remove() }

      #expect(try await harness.install(harness.plan([.platformTools])).result == .failure(expected))
      #expect(harness.stagingNames.isEmpty)
      #expect(!FileTree.exists(harness.sdk.appending(path: "platform-tools")))
      #expect(harness.removedDownloads.count == 1)
    }
  }

  @Test("푼 트리에 맨 위 폴더 밖을 가리키는 링크가 있으면 archiveUnsafe, 맨 위 폴더가 없으면 archiveUnreadable")
  func treeCheck() async throws {
    let escaping = try Harness(unzip: { spec, contents in
      try spec.extract(into: contents)
      try FileTree.link(contents, "\(spec.top)/escape", to: "../..")
      return .success()
    })
    defer { escaping.directory.remove() }
    #expect(try await escaping.install(escaping.plan([.platformTools]))
      .result == .failure(.archiveUnsafe(.platformTools)))
    #expect(escaping.stagingNames.isEmpty)
    #expect(!FileTree.exists(escaping.sdk.appending(path: "platform-tools")))

    let empty = try Harness(unzip: { _, _ in .success() })
    defer { empty.directory.remove() }
    #expect(try await empty.install(empty.plan([.platformTools]))
      .result == .failure(.archiveUnreadable(.platformTools)))
    #expect(empty.stagingNames.isEmpty)
  }

  @Test("최종 경로가 이름 바꾸기 직전에 생기면(RENAME_EXCL 실패) destinationExists, 기존 폴더 내용 그대로")
  func destinationExists() async throws {
    let sdkBox = Recorder<URL>()
    let harness = try Harness(unzip: { spec, contents in
      try spec.extract(into: contents)
      if let sdk = sdkBox.all.first {
        try FileTree.file(sdk, "platform-tools/studio.txt", contents: "studio")
      }
      return .success()
    })
    defer { harness.directory.remove() }
    sdkBox.append(harness.sdk)

    #expect(try await harness.install(harness.plan([.platformTools]))
      .result == .failure(.destinationExists(.platformTools)))
    #expect(FileTree.names(harness.sdk.appending(path: "platform-tools")) == ["studio.txt"])
    #expect(harness.stagingNames.isEmpty)
  }

  @Test("rename 실패: EEXIST → destinationExists, ENOTSUP 등 → sdkFolderUnavailable (대체 rename 없음)")
  func renameFailureMapping() {
    #expect(PackageInstaller.renameFailure(errno: EEXIST, component: .emulator) == .destinationExists(.emulator))
    #expect(PackageInstaller.renameFailure(errno: ENOTSUP, component: .emulator) == .sdkFolderUnavailable)
    #expect(PackageInstaller.renameFailure(errno: EXDEV, component: .emulator) == .sdkFolderUnavailable)
  }
}
