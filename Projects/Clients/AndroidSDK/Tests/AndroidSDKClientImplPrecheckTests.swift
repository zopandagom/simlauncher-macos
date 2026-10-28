import AndroidSDKInterface
import CommandInterface
import CommandTesting
import Core
import DownloadInterface
import DownloadTesting
import Foundation
import Testing
@testable import AndroidSDKImpl

/// `install(_:acceptedLicenses:progress:)` 의 시작 확인: 여유 공간·쓰기 확인, 고른 폴더, 모두 있음.
struct AndroidSDKClientImplPrecheckTests {
  // MARK: - 시작 확인

  @Test("미리 여유 확인: archive × 3 합 + 가장 큰 archive 가 같은 볼륨 여유보다 크면 받지 않고 insufficientDiskSpace")
  func precheckSameVolume() async throws {
    let harness = try Harness(capacity: { _ in 10 })
    defer { harness.directory.remove() }
    let plan = try harness.plan([.platformTools, .emulator])
    let sizes = plan.packages.map(\.archive.size)
    let required = sizes.reduce(0) { $0 + $1 * 3 } + (sizes.max() ?? 0)

    #expect(await harness.install(plan).result == .failure(.insufficientDiskSpace(
      .platformTools,
      required: required,
      available: 10
    )))
    #expect(harness.download.calls.isEmpty)
  }

  @Test("미리 여유 확인: 다른 볼륨이면 SDK 볼륨에 archive × 3 합, 받기 볼륨에 가장 큰 archive")
  func precheckOtherVolumes() async throws {
    let plan = { (harness: Harness) throws in try harness.plan([.platformTools, .emulator]) }
    let volume: @Sendable (URL) -> SDKVolume = { url in
      SDKVolume(
        device: url.path(percentEncoded: false).contains("downloads") ? 1 : 2,
        name: nil,
        supportsSymbolicLinks: true
      )
    }

    let sdkShort = try Harness(
      capacity: { url in url.path(percentEncoded: false).contains("downloads") ? .max : 5 },
      volume: volume
    )
    defer { sdkShort.directory.remove() }
    let sdkPlan = try plan(sdkShort)
    let estimate = sdkPlan.packages.reduce(0) { $0 + $1.archive.size * 3 }
    #expect(await sdkShort.install(sdkPlan).result == .failure(.insufficientDiskSpace(
      .platformTools,
      required: estimate,
      available: 5
    )))
    #expect(sdkShort.download.calls.isEmpty)

    let downloadsShort = try Harness(
      capacity: { url in url.path(percentEncoded: false).contains("downloads") ? 5 : .max },
      volume: volume
    )
    defer { downloadsShort.directory.remove() }
    let downloadsPlan = try plan(downloadsShort)
    let largest = downloadsPlan.packages.map(\.archive.size).max() ?? 0
    #expect(await downloadsShort.install(downloadsPlan).result
      == .failure(.insufficientDiskSpace(.platformTools, required: largest, available: 5)))

    let unknown = try Harness(capacity: { _ in nil }, volume: volume)
    defer { unknown.directory.remove() }
    #expect(await (try? unknown.install(try plan(unknown)).result.get()) != nil)
  }

  @Test("쓰기 확인: system-images 가 0o555 면 받지 않고 sdkFolderUnavailable")
  func precheckWritableAncestor() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    try FileTree.directory(harness.sdk, "system-images", mode: 0o555)
    let plan = try harness.plan()

    #expect(await harness.install(plan).result == .failure(.sdkFolderUnavailable))
    #expect(harness.download.calls.isEmpty)
  }

  @Test("쓰기 확인: 쓸 수 없는 루트(0o555)·링크 미지원 볼륨이면 받지 않고 sdkFolderUnavailable")
  func precheckRoot() async throws {
    let readOnly = try Harness()
    defer { readOnly.directory.remove() }
    try FileTree.directory(readOnly.sdk, "", mode: 0o555)
    #expect(try await readOnly.install(readOnly.plan()).result == .failure(.sdkFolderUnavailable))
    #expect(readOnly.download.calls.isEmpty)

    let usb = try Harness(volume: { _ in SDKVolume(device: 1, name: "USB", supportsSymbolicLinks: false) })
    defer { usb.directory.remove() }
    #expect(try await usb.install(usb.plan()).result == .failure(.sdkFolderUnavailable))
    #expect(usb.download.calls.isEmpty)
  }

  @Test("고른 폴더가 없으면 만들지 않고 sdkFolderUnavailable (기본 위치는 만든다)")
  func chosenRootNotCreated() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    let chosen = AndroidSDKRoot(url: harness.directory.child("chosen"), isDefault: false)
    harness.provider.set(.root(chosen))

    #expect(try await harness.install(harness.plan(root: chosen)).result == .failure(.sdkFolderUnavailable))
    #expect(!FileTree.exists(chosen.url))
    #expect(harness.download.calls.isEmpty)

    #expect(PackageInstaller.prepareRootIsCreated(harness.root))
  }

  @Test("최종 경로가 모두 있으면 쓰기·여유 확인 없이 alreadyPresent 로 끝난다")
  func allPresent() async throws {
    let harness = try Harness(capacity: { _ in 0 })
    defer { harness.directory.remove() }
    for component in AndroidSDKComponent.allCases {
      try FileTree.installed(component, in: harness.sdk)
    }

    let (result, progress) = try await harness.install(harness.plan())

    #expect(try result.get() == AndroidSDKInstallOutcome(
      installed: [],
      alreadyPresent: [.platformTools, .emulator, .systemImage]
    ))
    #expect(progress.isEmpty)
  }
}
