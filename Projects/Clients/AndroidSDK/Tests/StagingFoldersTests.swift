import Foundation
import Testing
@testable import AndroidSDKImpl

struct StagingFoldersTests {
  @Test("이름은 .simlauncher-staging-<UUID> 만 스테이징으로 본다")
  func names() {
    #expect(StagingFolders.isStagingName(StagingFolders.newName()))
    #expect(!StagingFolders.isStagingName(".simlauncher-staging-x"))
    #expect(!StagingFolders.isStagingName(".simlauncher-staging-"))
    #expect(!StagingFolders.isStagingName("simlauncher-staging-\(UUID().uuidString)"))
  }

  @Test("removeLeftovers: 등록되지 않은 스테이징만 지우고, 읽기 전용 하위 폴더가 있어도 모두 지운다")
  func removesUnregistered() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let root = directory.url.path(percentEncoded: false)
    let folders = StagingFolders()
    let live = StagingFolders.newName()
    let old = StagingFolders.newName()
    folders.register(live)
    try FileTree.directory(directory.url, live)
    try FileTree.file(directory.url, "\(old)/contents/arm64-v8a/system.img")
    try FileTree.directory(directory.url, "\(old)/contents/arm64-v8a/data", mode: 0o500)
    try FileTree.directory(directory.url, "\(old)/contents/locked", mode: 0o000)

    folders.removeLeftovers(root: root)

    #expect(FileTree.names(directory.url) == [live])
  }

  @Test("이름이 틀린 폴더·링크·다른 부모의 스테이징은 지우지 않는다")
  func keepsOthers() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let sdk = directory.child("sdk")
    let other = directory.child("other")
    let folders = StagingFolders()
    let otherStaging = StagingFolders.newName()
    try FileTree.directory(other, otherStaging)
    try FileTree.directory(sdk, ".simlauncher-staging-wrong")
    try FileTree.link(
      sdk,
      StagingFolders.newName(),
      to: other.appending(path: otherStaging).path(percentEncoded: false)
    )

    folders.removeLeftovers(root: sdk.path(percentEncoded: false))
    folders.remove(
      other.appending(path: otherStaging, directoryHint: .isDirectory),
      root: sdk.path(percentEncoded: false)
    )

    #expect(FileTree.names(sdk).count == 2)
    #expect(FileTree.names(other) == [otherStaging])
  }

  @Test("remove: 형식에 맞으면 지우고 등록을 푼다")
  func removeUnregisters() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let folders = StagingFolders()
    let name = StagingFolders.newName()
    folders.register(name)
    try FileTree.directory(directory.url, name)

    folders.remove(
      directory.url.appending(path: name, directoryHint: .isDirectory),
      root: directory.url.path(percentEncoded: false)
    )

    #expect(!folders.isLive(name))
    #expect(FileTree.names(directory.url).isEmpty)
  }
}
