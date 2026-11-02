import AndroidSDKInterface
import Core
import Foundation
import Synchronization
import Testing
@testable import AndroidSDKImpl

/// 볼륨 값을 링크를 따라간 실제 경로에서 읽기(`SDKFiles.volumeLocation`, Impl init 의 감싸기)와
/// 받을 패키지 폴더가 SDK 위치와 다른 볼륨이면 받기 전에 거절하기.
/// 실제 다른 볼륨(외장 디스크)은 단위 테스트로 만들 수 없어, 주입 볼륨이 실제 경로에 따라 다른 값을 돌려준다.
struct AndroidSDKClientImplVolumeTests {
  /// `url` 이 `base` 와 같거나 그 아래다 (끝 `/` 는 무시한다).
  static func isUnder(_ url: URL, _ base: URL) -> Bool {
    RealPath.isWithin(
      SDKFiles.withoutTrailingSlash(url.path(percentEncoded: false)),
      SDKFiles.withoutTrailingSlash(base.path(percentEncoded: false))
    )
  }

  static func path(_ url: URL) -> String {
    SDKFiles.withoutTrailingSlash(url.path(percentEncoded: false))
  }

  // MARK: - volumeLocation

  @Test("volumeLocation: 링크·끝 / 가 붙은 링크·조상이 링크인 경로는 실제 경로로 푼다")
  func volumeLocationResolvesLinks() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let target = directory.child("target")
    try FileTree.directory(target, "child")
    try FileTree.link(directory.url, "link", to: Self.path(target))
    let link = directory.url.appending(path: "link", directoryHint: .notDirectory)

    #expect(Self.path(SDKFiles.volumeLocation(link)) == Self.path(target))
    #expect(Self.path(SDKFiles.volumeLocation(URL(filePath: Self.path(link) + "/"))) == Self.path(target))
    #expect(
      Self.path(SDKFiles.volumeLocation(link.appending(path: "child", directoryHint: .isDirectory)))
        == Self.path(target.appending(path: "child"))
    )
  }

  @Test("volumeLocation: 없는 경로·링크 루프는 받은 URL 그대로")
  func volumeLocationKeepsUnresolvable() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let missing = directory.child("missing")
    try FileTree.link(directory.url, "a", to: Self.path(directory.url.appending(path: "b")))
    try FileTree.link(directory.url, "b", to: Self.path(directory.url.appending(path: "a")))
    let loop = directory.url.appending(path: "a", directoryHint: .notDirectory)

    #expect(SDKFiles.volumeLocation(missing) == missing)
    #expect(SDKFiles.volumeLocation(loop) == loop)
  }

  // MARK: - 받을 패키지 폴더의 볼륨

  /// `sdk/system-images` 가 `other/system-images` 를 가리키는 링크이고, 주입 볼륨이 `other` 아래 실제 경로만 `otherDevice` 로 읽는 Harness.
  static func linkedSystemImages(otherDevice: UInt64) throws -> (harness: Harness, other: URL) {
    let otherBox = OtherFolder()
    let harness = try Harness(volume: { url in
      SDKVolume(
        device: otherBox.contains(url) ? otherDevice : 1,
        name: "Test",
        supportsSymbolicLinks: true
      )
    })
    let other = harness.directory.child("other")
    otherBox.set(other)
    try FileTree.directory(other, "system-images")
    try FileTree.directory(harness.sdk, "")
    try FileTree.link(harness.sdk, "system-images", to: Self.path(other.appending(path: "system-images")))
    return (harness, other)
  }

  @Test("system-images 가 다른 볼륨을 가리키면 받지 않고 packageFolderOnOtherVolume, SDK·다른 볼륨에 아무것도 만들지 않는다")
  func otherVolumeRejectedBeforeDownload() async throws {
    let (harness, other) = try Self.linkedSystemImages(otherDevice: 2)
    defer { harness.directory.remove() }

    let result = try await harness.install(harness.plan()).result

    #expect(result == .failure(.packageFolderOnOtherVolume(.systemImage)))
    #expect(harness.downloadCount == 0)
    #expect(harness.download.calls.isEmpty)
    #expect(FileTree.names(harness.sdk) == ["system-images"])
    #expect(FileTree.names(other.appending(path: "system-images")).isEmpty)
  }

  @Test("system-images 링크가 같은 볼륨의 다른 폴더면 통과해 링크 너머에 설치한다")
  func sameVolumeLinkInstalls() async throws {
    let (harness, other) = try Self.linkedSystemImages(otherDevice: 1)
    defer { harness.directory.remove() }

    let outcome = try await harness.install(harness.plan()).result.get()

    #expect(outcome.installed == [.platformTools, .emulator, .systemImage])
    let image = other.appending(path: "system-images/android-37.0/google_apis/arm64-v8a/system.img")
    #expect(FileTree.read(image) == "img")
  }

  @Test("최종 경로의 부모가 루트인 패키지(platform-tools·emulator)는 다른 볼륨 검사에 걸리지 않는다")
  func rootLevelPackagesUnaffected() async throws {
    let (harness, _) = try Self.linkedSystemImages(otherDevice: 2)
    defer { harness.directory.remove() }

    let outcome = try await harness.install(harness.plan([.platformTools, .emulator])).result.get()

    #expect(outcome.installed == [.platformTools, .emulator])
  }

  @Test("최종 경로가 이미 있으면(다른 볼륨 링크라도) 받지 않을 패키지라 검사하지 않고 건너뛴다")
  func existingDestinationSkipped() async throws {
    let (harness, other) = try Self.linkedSystemImages(otherDevice: 2)
    defer { harness.directory.remove() }
    try FileTree.installed(.systemImage, in: other)

    let outcome = try await harness.install(harness.plan()).result.get()

    #expect(outcome.installed == [.platformTools, .emulator])
    #expect(outcome.alreadyPresent == [.systemImage])
  }

  @Test("device 를 읽지 못하면 확인하지 못한 것으로 보고 진행한다")
  func unknownDeviceProceeds() async throws {
    let otherBox = OtherFolder()
    let harness = try Harness(volume: { url in
      SDKVolume(device: otherBox.contains(url) ? nil : 1, name: "Test", supportsSymbolicLinks: true)
    })
    defer { harness.directory.remove() }
    let other = harness.directory.child("other")
    otherBox.set(other)
    try FileTree.directory(other, "system-images")
    try FileTree.directory(harness.sdk, "")
    try FileTree.link(harness.sdk, "system-images", to: Self.path(other.appending(path: "system-images")))

    let outcome = try await harness.install(harness.plan()).result.get()

    #expect(outcome.installed == [.platformTools, .emulator, .systemImage])
  }

  // MARK: - 링크인 SDK 루트의 볼륨 값

  struct LinkedRoot {
    let harness: Harness
    let root: AndroidSDKRoot
    let real: URL
    var pair: (Harness, AndroidSDKRoot) { (self.harness, self.root) }
  }

  /// SDK 루트가 `real` 을 가리키는 링크(`link`)인 Harness. 주입 함수는 `real` 아래 실제 경로에만 다른 값을 돌려준다.
  static func linkedRoot(
    capacity: @escaping @Sendable (_ underReal: Bool) -> Int64? = { _ in .max },
    volume: @escaping @Sendable (_ underReal: Bool) -> SDKVolume = { _ in
      SDKVolume(device: 1, name: "Test", supportsSymbolicLinks: true)
    }
  ) throws -> LinkedRoot {
    let realBox = OtherFolder()
    let harness = try Harness(
      capacity: { capacity(realBox.contains($0)) },
      volume: { volume(realBox.contains($0)) }
    )
    let real = harness.directory.child("realsdk")
    realBox.set(real)
    try FileTree.directory(real, "")
    try FileTree.link(harness.directory.url, "sdklink", to: Self.path(real))
    let root = AndroidSDKRoot(url: harness.directory.child("sdklink"), isDefault: false)
    harness.provider.set(.root(root))
    return LinkedRoot(harness: harness, root: root, real: real)
  }

  @Test("링크인 SDK 루트: 여유 공간은 링크 너머 실제 경로의 볼륨으로 비교한다")
  func linkedRootCapacity() async throws {
    let (harness, root) = try Self.linkedRoot(capacity: { $0 ? 5 : .max }).pair
    defer { harness.directory.remove() }
    let plan = try harness.plan(root: root)
    let sizes = plan.packages.map(\.archive.size)
    let required = sizes.reduce(0) { $0 + $1 * 3 } + (sizes.max() ?? 0)

    #expect(await harness.install(plan).result == .failure(.insufficientDiskSpace(
      .platformTools,
      required: required,
      available: 5
    )))
    #expect(harness.download.calls.isEmpty)
  }

  @Test("링크인 SDK 루트: 볼륨 성질은 실제 경로에서 읽어 확인의 설치 막힘과 계획의 sdkFolderUnavailable 이 된다")
  func linkedRootVolumeSupport() async throws {
    let harness = try Self.linkedRoot(volume: { underReal in
      SDKVolume(device: 1, name: "Test", supportsSymbolicLinks: !underReal)
    }).harness
    defer { harness.directory.remove() }

    #expect(await harness.client.checkSDK().installBlocker == .unsupportedVolume)
    #expect(await harness.planResult() == .failure(.sdkFolderUnavailable))
  }

  @Test("링크인 SDK 루트: 계획의 볼륨 이름은 실제 경로 쪽 값")
  func linkedRootVolumeName() async throws {
    let linked = try Self.linkedRoot(volume: { underReal in
      SDKVolume(device: 1, name: underReal ? "External" : "Macintosh HD", supportsSymbolicLinks: true)
    })
    let (harness, root, real) = (linked.harness, linked.root, linked.real)
    defer { harness.directory.remove() }
    for component in AndroidSDKComponent.allCases {
      try FileTree.installed(component, in: real)
    }

    let plan = try await harness.planResult().get()

    #expect(plan.isEmpty)
    #expect(plan.root == root)
    #expect(plan.sdkVolumeName == "External")
  }
}

/// 주입 볼륨이 볼 폴더. Harness 를 만든 뒤(임시 폴더가 정해진 뒤) 정한다.
private final class OtherFolder: Sendable {
  private let folder = Mutex<URL?>(nil)

  func set(_ url: URL) {
    self.folder.withLock { $0 = url }
  }

  /// 정한 폴더와 같거나 그 아래다 (끝 `/` 는 무시한다).
  func contains(_ url: URL) -> Bool {
    guard let folder = self.folder.withLock({ $0 }) else {
      return false
    }
    return AndroidSDKClientImplVolumeTests.isUnder(url, folder)
  }
}
