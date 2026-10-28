import AndroidSDKInterface
import CommandInterface
import CommandTesting
import Core
import DownloadInterface
import DownloadTesting
import Foundation
import Synchronization
import Testing
@testable import AndroidSDKImpl

/// 설치 취소: 받기·풀기·마무리 중. 멈춤이 풀리지 않는 회귀에서도 멈추지 않게 끝나기는 `waitUntil`(10초 상한)로 본다.
struct AndroidSDKClientImplCancelTests {
  typealias InstallResult = Result<AndroidSDKInstallOutcome, AndroidSDKInstallError>

  @Test("받기 중 취소: cancelled, 스테이징 없음, 앞서 끝난 패키지는 남는다")
  func cancelWhileDownloading() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    let plan = try harness.plan([.platformTools, .emulator])
    let download = harness.download
    let task = Task<InstallResult, Never> {
      await harness.install(plan) { progress in
        if progress.component == .platformTools, progress.phase == .finishing {
          download.suspendDownloads()
        }
      }.result
    }

    try await waitUntil { download.suspendedDownloadCount == 1 }
    task.cancel()

    #expect(await task.value == .failure(.cancelled))
    #expect(FileTree.exists(harness.sdk.appending(path: "platform-tools/adb")))
    #expect(!FileTree.exists(harness.sdk.appending(path: "emulator")))
    #expect(harness.stagingNames.isEmpty)
    #expect(harness.executables == [PackageZipCommand.zipinfo, PackageZipCommand.unzip])
  }

  @Test("풀기 중 취소: cancelled, 스테이징·받은 폴더 지움, 최종 경로 없음")
  func cancelWhileExtracting() async throws {
    let started = Mutex(false)
    let harness = try Harness(cancellableUnzip: { invocation, _ throws(CommandError) in
      let contents = URL(filePath: invocation.arguments[4], directoryHint: .isDirectory)
      try? FileTree.file(contents, "platform-tools/half", contents: "partial")
      started.withLock { $0 = true }
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(2))
      }
      throw .cancelled
    })
    defer { harness.directory.remove() }
    let plan = try harness.plan([.platformTools])
    let task = Task<InstallResult, Never> { await harness.install(plan).result }

    try await waitUntil { started.withLock { $0 } }
    task.cancel()

    #expect(await task.value == .failure(.cancelled))
    #expect(harness.stagingNames.isEmpty)
    #expect(harness.removedDownloads.count == 1)
    #expect(!FileTree.exists(harness.sdk.appending(path: "platform-tools")))
  }

  @Test("풀기는 끝났는데 마무리 직전에 취소됐으면 cancelled, 스테이징 지움")
  func cancelBeforeFinishing() async throws {
    let harness = try Harness(cancellableUnzip: { invocation, _ throws(CommandError) in
      let contents = URL(filePath: invocation.arguments[4], directoryHint: .isDirectory)
      try? PackageSpec(.platformTools).extract(into: contents)
      withUnsafeCurrentTask { $0?.cancel() }
      return .success()
    })
    defer { harness.directory.remove() }

    let plan = try harness.plan([.platformTools])
    let result = await Task<InstallResult, Never> { await harness.install(plan).result }.value

    #expect(result == .failure(.cancelled))
    #expect(harness.stagingNames.isEmpty)
    #expect(!FileTree.exists(harness.sdk.appending(path: "platform-tools")))
  }

  @Test("마무리 중 취소: 그 패키지는 끝까지 설치하고, 다음 패키지는 받지 않고 cancelled")
  func cancelWhileFinishing() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    let plan = try harness.plan([.platformTools, .emulator])

    let result = await Task<InstallResult, Never> {
      await harness.install(plan) { progress in
        if progress.phase == .finishing {
          withUnsafeCurrentTask { $0?.cancel() }
        }
      }.result
    }.value

    #expect(result == .failure(.cancelled))
    #expect(FileTree.exists(harness.sdk.appending(path: "platform-tools/adb")))
    #expect(harness.stagingNames.isEmpty)
    #expect(!harness.download.calls.contains(.download(PackageSpec(.emulator).url.url)))
  }

  @Test("시작 전에 취소된 Task 면 아무것도 받지 않고 cancelled")
  func cancelledBeforeStart() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    let plan = try harness.plan()

    let result = await Task<InstallResult, Never> {
      withUnsafeCurrentTask { $0?.cancel() }
      return await harness.install(plan).result
    }.value

    #expect(result == .failure(.cancelled))
    #expect(harness.download.calls.isEmpty)
  }
}
