import AndroidSDKInterface
import CommandTesting
import Core
import DownloadTesting
import Foundation
import Testing
@testable import AndroidSDKImpl

/// `checkSDK()`·`inspectCandidateFolder(_:)`·`removeLeftovers()` (임시 폴더를 SDK 루트로 주입, 명령·네트워크 없음).
struct AndroidSDKClientImplStatusTests {
  static func harness(_ root: AndroidSDKRootChoice? = nil, volume: SDKVolume? = nil) throws -> Harness {
    if let volume {
      return try Harness(root: root, volume: { _ in volume })
    }
    return try Harness(root: root)
  }

  // MARK: - 위치

  @Test("기본 위치가 없으면 absent·셋 다 없음, 고른 폴더가 없으면 unusable(.missing) 이고 만들지 않는다")
  func absentRoot() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }

    let status = await harness.client.checkSDK()
    #expect(status.location == .absent(harness.root))
    #expect(status.missing == Set(AndroidSDKComponent.allCases))
    #expect(status.canInstallMissing)

    let chosen = AndroidSDKRoot(url: harness.directory.child("chosen"), isDefault: false)
    harness.provider.set(.root(chosen))
    #expect(await harness.client.checkSDK().location == .unusable(chosen, .missing))
    #expect(!FileTree.exists(chosen.url))
    #expect(harness.command.invocations.isEmpty)
    #expect(harness.download.calls.isEmpty)
  }

  @Test("빈 폴더면 셋 다 없음, 파일인 루트는 notDirectory, 깨진 링크는 brokenLink, 잘못된 설정은 invalidSetting")
  func rootKinds() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }

    try FileTree.directory(harness.sdk, "")
    #expect(await harness.client.checkSDK().location == .folder(harness.root, writable: true))
    #expect(await harness.client.checkSDK().missing == Set(AndroidSDKComponent.allCases))

    try FileTree.file(harness.directory.url, "file-root")
    let fileRoot = AndroidSDKRoot(url: harness.directory.child("file-root"), isDefault: false)
    harness.provider.set(.root(fileRoot))
    #expect(await harness.client.checkSDK().location == .unusable(fileRoot, .notDirectory))

    try FileTree.link(
      harness.directory.url,
      "broken",
      to: harness.directory.child("nowhere").path(percentEncoded: false)
    )
    let broken = AndroidSDKRoot(url: harness.directory.child("broken"), isDefault: false)
    harness.provider.set(.root(broken))
    #expect(await harness.client.checkSDK().location == .unusable(broken, .brokenLink))

    harness.provider.set(.invalidSetting)
    #expect(await harness.client.checkSDK().location == .unusable(nil, .invalidSetting))
  }

  @Test("디렉터리를 가리키는 링크면 따라가 구성 요소를 판정한다 (위치는 링크 경로)")
  func linkToDirectory() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }
    let real = harness.directory.child("real-sdk")
    try FileTree.installed(.platformTools, in: real)
    try FileTree.link(harness.directory.url, "linked", to: real.path(percentEncoded: false))
    let linked = AndroidSDKRoot(url: harness.directory.child("linked"), isDefault: false)
    harness.provider.set(.root(linked))

    let status = await harness.client.checkSDK()

    #expect(status.location == .folder(linked, writable: true))
    #expect(status.components[.platformTools] == .installed(AndroidRevision(major: 37, minor: 0, micro: 1)))
  }

  // MARK: - 구성 요소

  @Test("셋 다 설치됨: source.properties 의 revision, 시스템 이미지 API 이름")
  func installedAll() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }
    for component in AndroidSDKComponent.allCases {
      try FileTree.installed(component, in: harness.sdk)
    }

    let status = await harness.client.checkSDK()

    #expect(status.isReady)
    #expect(status.components[.emulator] == .installed(AndroidRevision(major: 37, minor: 2, micro: 12)))
    #expect(status.components[.systemImage] == .installed(AndroidRevision(major: 7)))
    #expect(status.installedSystemImages == ["android-37.0"])
    #expect(harness.command.invocations.isEmpty)
  }

  @Test("platform-tools 폴더만 있고 adb 없음 → executableMissing, 실행 권한 없음 → notExecutable")
  func toolProblems() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }
    try FileTree.directory(harness.sdk, "platform-tools")
    try FileTree.file(harness.sdk, "emulator/emulator", mode: 0o644)

    let status = await harness.client.checkSDK()

    #expect(status.components[.platformTools] == .unusable(.executableMissing))
    #expect(status.components[.emulator] == .unusable(.notExecutable))
    #expect(status.missing == [.systemImage])
  }

  @Test("adb 가 실행 파일을 가리키는 링크면 설치됨")
  func executableLink() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }
    try FileTree.file(harness.directory.url, "real-adb", mode: 0o755)
    try FileTree.link(
      harness.sdk,
      "platform-tools/adb",
      to: harness.directory.url.appending(path: "real-adb", directoryHint: .notDirectory).path(percentEncoded: false)
    )

    #expect(await harness.client.checkSDK().components[.platformTools] == .installed(nil))
  }

  @Test("시스템 이미지: 호스트 abi 폴더에 system.img 없음 → imageFilesMissing, 다른 abi 만 있음 → missing, 다른 태그도 설치됨")
  func systemImages() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }

    try FileTree.file(harness.sdk, "system-images/android-37.0/google_apis/x86_64/system.img")
    #expect(await harness.client.checkSDK().components[.systemImage] == .missing)

    try FileTree.directory(harness.sdk, "system-images/android-37.0/google_apis/arm64-v8a")
    #expect(await harness.client.checkSDK().components[.systemImage] == .unusable(.imageFilesMissing))

    try FileTree.file(harness.sdk, "system-images/android-36/google_apis_playstore/arm64-v8a/system.img")
    let status = await harness.client.checkSDK()
    #expect(status.components[.systemImage] == .installed(nil))
    #expect(status.installedSystemImages == ["android-36"])
  }

  @Test("쓸 수 없는 루트(0o555)는 folder(writable: false) 와 notWritable, system-images 0o555 는 그 폴더로 막는다")
  func notWritable() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }
    try FileTree.directory(harness.sdk, "system-images", mode: 0o555)

    let images = await harness.client.checkSDK()
    #expect(images.installBlocker == .notWritable(harness.root.folder(for: .systemImage)))
    #expect(!images.canInstallMissing)

    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555],
      ofItemAtPath: harness.sdk.path(percentEncoded: false)
    )
    let root = await harness.client.checkSDK()
    #expect(root.location == .folder(harness.root, writable: false))
    #expect(root.installBlocker == .notWritable(harness.root.url))
  }

  @Test("링크를 지원하지 않는 볼륨이면 unsupportedVolume")
  func unsupportedVolume() async throws {
    let harness = try Self.harness(volume: SDKVolume(device: 1, name: "USB", supportsSymbolicLinks: false))
    defer { harness.directory.remove() }

    #expect(await harness.client.checkSDK().installBlocker == .unsupportedVolume)
  }

  @Test("provider 는 공개 메서드마다 한 번 부른다 (후보 판정은 부르지 않는다)")
  func providerOncePerCall() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }

    _ = await harness.client.checkSDK()
    #expect(harness.provider.calls == 1)
    await harness.client.removeLeftovers()
    #expect(harness.provider.calls == 2)
    _ = await harness.planResult()
    #expect(harness.provider.calls == 3)
    _ = await harness.client.inspectCandidateFolder(harness.directory.url)
    #expect(harness.provider.calls == 3)
  }

  // MARK: - 후보

  @Test("후보: 빈 폴더(.DS_Store 만) → empty, SDK 폴더 → sdk, 다른 내용 → otherContents, 없음 → missing, 파일 → notDirectory")
  func candidates() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }
    let base = harness.directory.url
    try FileTree.file(base, "empty/.DS_Store")
    try FileTree.directory(base, "sdk-like/platform-tools")
    try FileTree.file(base, "sdk-like/.knownPackages")
    try FileTree.file(base, "documents/notes.txt")
    try FileTree.file(base, "file")

    #expect(await harness.client.inspectCandidateFolder(harness.directory.child("empty")) == (.empty, true))
    #expect(await harness.client.inspectCandidateFolder(harness.directory.child("sdk-like")) == (.sdk, true))
    #expect(await harness.client.inspectCandidateFolder(harness.directory.child("documents")) == (.otherContents, true))
    #expect(await harness.client.inspectCandidateFolder(harness.directory.child("none")).candidate == .missing)
    #expect(await harness.client.inspectCandidateFolder(harness.directory.child("file")).candidate == .notDirectory)
    #expect(harness.command.invocations.isEmpty)
  }

  @Test("후보: 링크면 따라간 폴더를 보고, 쓸 수 없는 폴더·system-images 면 writable false")
  func candidateWritable() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }
    let base = harness.directory.url
    try FileTree.directory(base, "readonly", mode: 0o555)
    try FileTree.directory(base, "images/system-images", mode: 0o555)
    try FileTree.directory(base, "target/platform-tools")
    try FileTree.link(base, "link", to: harness.directory.child("target").path(percentEncoded: false))

    #expect(await harness.client.inspectCandidateFolder(harness.directory.child("readonly")) == (.empty, false))
    #expect(await harness.client.inspectCandidateFolder(harness.directory.child("images")) == (.sdk, false))
    #expect(await harness.client.inspectCandidateFolder(harness.directory.child("link")) == (.sdk, true))
  }

  @Test("후보: 링크를 지원하지 않는 볼륨이면 unsupportedVolume")
  func candidateUnsupportedVolume() async throws {
    let harness = try Self.harness(volume: SDKVolume(device: 2, name: "USB", supportsSymbolicLinks: false))
    defer { harness.directory.remove() }

    #expect(await harness.client.inspectCandidateFolder(harness.directory.url).candidate == .unsupportedVolume)
  }

  // MARK: - 남은 정리

  @Test("removeLeftovers: 남은 스테이징만 지우고 다른 항목은 그대로, removeLeftoverDownloads 를 부른다")
  func removeLeftovers() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }
    let leftover = StagingFolders.prefix + UUID().uuidString
    try FileTree.file(harness.sdk, "\(leftover)/contents/arm64-v8a/system.img")
    try FileTree.directory(harness.sdk, "\(leftover)/contents/arm64-v8a/locked", mode: 0o500)
    try FileTree.directory(harness.sdk, "\(StagingFolders.prefix)not-a-uuid")
    try FileTree.directory(harness.sdk, "platform-tools")
    try FileTree.directory(harness.directory.url, "outside")
    try FileTree.link(
      harness.sdk,
      StagingFolders.prefix + UUID().uuidString,
      to: harness.directory.child("outside").path(percentEncoded: false)
    )

    await harness.client.removeLeftovers()

    let names = FileTree.names(harness.sdk)
    #expect(!names.contains(leftover))
    #expect(names.contains("\(StagingFolders.prefix)not-a-uuid"))
    #expect(names.contains("platform-tools"))
    #expect(names.count == 3)
    #expect(FileTree.exists(harness.directory.child("outside")))
    #expect(harness.download.leftoverCleanupCount == 1)
  }

  @Test("removeLeftovers: 지금 위치만 정리하고, 위치가 없어도 받기 폴더 정리는 부른다")
  func removeLeftoversCurrentRootOnly() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }
    let leftover = StagingFolders.prefix + UUID().uuidString
    try FileTree.directory(harness.sdk, leftover)
    let other = AndroidSDKRoot(url: harness.directory.child("other"), isDefault: false)
    harness.provider.set(.root(other))

    await harness.client.removeLeftovers()

    #expect(FileTree.names(harness.sdk) == [leftover])
    #expect(harness.download.leftoverCleanupCount == 1)
  }
}
