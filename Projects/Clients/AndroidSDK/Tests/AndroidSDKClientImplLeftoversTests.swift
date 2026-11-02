import AndroidSDKInterface
import Core
import Foundation
import Testing
@testable import AndroidSDKImpl

/// 지금 위치가 아닌 루트의 남은 스테이징 정리 (`removeLeftovers(in:)`). 설정에서 위치를 바꿀 때 이전 위치에 쓴다.
struct AndroidSDKClientImplLeftoversTests {
  static func path(_ url: URL) -> String {
    SDKFiles.withoutTrailingSlash(url.path(percentEncoded: false))
  }

  @Test("removeLeftovers(in:): 지금 위치가 아닌 루트의 형식 맞는 스테이징만 지우고, provider·받기 정리는 부르지 않는다")
  func removeLeftoversInOtherRoot() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    let old = harness.directory.child("old")
    let leftover = StagingFolders.newName()
    let live = StagingFolders.newName()
    harness.client.staging.register(live)
    try FileTree.file(old, "\(leftover)/contents/arm64-v8a/system.img")
    try FileTree.directory(old, "\(leftover)/contents/locked", mode: 0o500)
    try FileTree.directory(old, live)
    try FileTree.directory(old, "\(StagingFolders.prefix)not-a-uuid")
    try FileTree.directory(old, "platform-tools")
    try FileTree.directory(harness.directory.url, "outside")
    let linked = StagingFolders.newName()
    try FileTree.link(old, linked, to: Self.path(harness.directory.child("outside")))
    let currentLeftover = StagingFolders.newName()
    try FileTree.directory(harness.sdk, currentLeftover)

    await harness.client.removeLeftovers(in: AndroidSDKRoot(url: old, isDefault: false))

    #expect(FileTree.names(old) == [live, linked, "\(StagingFolders.prefix)not-a-uuid", "platform-tools"].sorted())
    #expect(FileTree.exists(harness.directory.child("outside")))
    #expect(FileTree.names(harness.sdk) == [currentLeftover])
    #expect(harness.provider.calls == 0)
    #expect(harness.download.leftoverCleanupCount == 0)
  }

  @Test("removeLeftovers(in:): 링크인 루트는 실제 폴더를 정리한다")
  func removeLeftoversInLinkedRoot() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    let real = harness.directory.child("real")
    let leftover = StagingFolders.newName()
    try FileTree.directory(real, leftover)
    try FileTree.link(harness.directory.url, "alias", to: Self.path(real))

    await harness.client.removeLeftovers(
      in: AndroidSDKRoot(url: harness.directory.child("alias"), isDefault: false)
    )

    #expect(FileTree.names(real).isEmpty)
  }

  @Test("removeLeftovers(in:): 루트가 없거나 파일이면 아무것도 하지 않는다")
  func removeLeftoversInUnusableRoot() async throws {
    let harness = try Harness()
    defer { harness.directory.remove() }
    try FileTree.file(harness.directory.url, "file")

    await harness.client.removeLeftovers(in: AndroidSDKRoot(url: harness.directory.child("missing"), isDefault: false))
    await harness.client.removeLeftovers(in: AndroidSDKRoot(url: harness.directory.child("file"), isDefault: false))

    #expect(FileTree.names(harness.directory.url) == ["downloads", "file"])
    #expect(harness.download.leftoverCleanupCount == 0)
  }
}
