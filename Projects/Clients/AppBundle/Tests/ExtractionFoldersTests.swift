import Foundation
import Testing
@testable import AppBundleImpl

/// 임시 폴더를 tmp 로 주입해 정리를 검사한다. 테스트마다 폴더를 지운다.
struct ExtractionFoldersTests {
  private static func folderName() -> String {
    "SimLauncher-Unzip-\(UUID().uuidString)"
  }

  /// zip 이 만들 수 있는 지우기 어려운 권한 트리 (critic nested-perm·perm 과 같은 모양).
  private static func makeHardToRemoveTree(_ folder: URL) throws {
    try FileTree.file(folder, "contents/Sample.app/Info.plist")
    try FileTree.file(folder, "contents/Sample.app/ro/f")
    try FileTree.directory(folder, "contents/Sample.app/ro", mode: 0o555)
    try FileTree.file(folder, "contents/Sample.app/outer/inner/f")
    try FileTree.directory(folder, "contents/Sample.app/outer/inner", mode: 0o555)
    try FileTree.directory(folder, "contents/Sample.app/outer", mode: 0o111)
    for mode: Int16 in [0o222, 0o333, 0o100, 0o500, 0o000] {
      let path = "contents/Sample.app/d\(String(mode, radix: 8))"
      try FileTree.file(folder, "\(path)/sub/f")
      try FileTree.file(folder, "\(path)/f")
      try FileTree.directory(folder, path, mode: mode)
    }
  }

  @Test("remove 는 0o555·0o111 안 0o555·0o222·0o333·0o100·0o500·0o000 폴더가 든 트리도 남김없이 지운다")
  func removeHardTree() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let folders = ExtractionFolders(temporaryDirectory: directory.url)
    let folder = directory.url.appending(path: Self.folderName(), directoryHint: .isDirectory)
    try Self.makeHardToRemoveTree(folder)

    folders.remove(folder)

    #expect(!FileTree.exists(folder))
  }

  @Test("leftover 정리는 형식에 맞는 폴더만 지운다: UUID 아닌 이름·다른 폴더·같은 이름의 링크·파일은 남긴다")
  func removeLeftoversOnlyMatching() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let tmp = directory.url.appending(path: "tmp", directoryHint: .isDirectory)
    let outside = directory.url.appending(path: "outside", directoryHint: .isDirectory)
    try FileTree.file(outside, "keep")
    try FileTree.directory(directory.url, "outside", mode: 0o500)
    let leftover = tmp.appending(path: Self.folderName(), directoryHint: .isDirectory)
    try Self.makeHardToRemoveTree(leftover)
    let notUUID = tmp.appending(path: "SimLauncher-Unzip-not-a-uuid")
    let other = tmp.appending(path: "Other")
    let link = tmp.appending(path: Self.folderName())
    let file = tmp.appending(path: Self.folderName())
    try FileTree.directory(notUUID, "")
    try FileTree.directory(other, "")
    try FileTree.link(tmp, link.lastPathComponent, to: outside.path(percentEncoded: false))
    try FileTree.file(tmp, file.lastPathComponent)

    ExtractionFolders(temporaryDirectory: tmp).removeLeftovers()

    #expect(!FileTree.exists(leftover))
    #expect(FileTree.exists(notUUID))
    #expect(FileTree.exists(other))
    #expect(FileTree.exists(link))
    #expect(FileTree.exists(file))
    #expect(FileTree.exists(outside.appending(path: "keep")))
    #expect(FileTree.mode(outside) == 0o500)
  }

  @Test("leftover 정리는 등록된 폴더를 건너뛰고, 등록을 푼 뒤에는 지운다")
  func liveFoldersAreSkipped() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let folders = ExtractionFolders(temporaryDirectory: directory.url)
    let name = Self.folderName()
    let folder = directory.url.appending(path: name, directoryHint: .isDirectory)
    try FileTree.file(folder, "contents/Sample.app/Info.plist")
    folders.register(name)

    folders.removeLeftovers()
    #expect(FileTree.exists(folder))

    folders.unregister(name)
    folders.removeLeftovers()
    #expect(!FileTree.exists(folder))
  }

  @Test("remove 는 형식이 아닌 경로를 무시한다: 다른 부모, UUID 아닌 이름, 링크")
  func removeIgnoresOtherPaths() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let tmp = directory.url.appending(path: "tmp", directoryHint: .isDirectory)
    try FileTree.directory(tmp, "")
    let folders = ExtractionFolders(temporaryDirectory: tmp)
    let otherParent = directory.url.appending(path: Self.folderName(), directoryHint: .isDirectory)
    let notUUID = tmp.appending(path: "SimLauncher-Unzip-x", directoryHint: .isDirectory)
    let target = directory.url.appending(path: "target", directoryHint: .isDirectory)
    let link = tmp.appending(path: Self.folderName(), directoryHint: .isDirectory)
    try FileTree.file(otherParent, "f")
    try FileTree.file(notUUID, "f")
    try FileTree.file(target, "f")
    try FileTree.directory(directory.url, "target", mode: 0o500)
    try FileTree.link(tmp, link.lastPathComponent, to: target.path(percentEncoded: false))

    for url in [otherParent, notUUID, link] {
      folders.remove(url)
    }

    #expect(FileTree.exists(otherParent.appending(path: "f")))
    #expect(FileTree.exists(notUUID.appending(path: "f")))
    #expect(FileTree.exists(link))
    #expect(FileTree.exists(target.appending(path: "f")))
    #expect(FileTree.mode(target) == 0o500)
  }

  @Test("tmp 를 링크를 거친 경로로 주입해도 그 안의 폴더를 지운다")
  func temporaryDirectoryThroughLink() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    try FileTree.directory(directory.url, "real")
    try FileTree.link(directory.url, "alias", to: "real")
    let alias = directory.url.appending(path: "alias", directoryHint: .isDirectory)
    let folder = alias.appending(path: Self.folderName(), directoryHint: .isDirectory)
    try FileTree.file(folder, "f")

    ExtractionFolders(temporaryDirectory: alias).remove(folder)

    #expect(!FileTree.exists(folder))
  }
}
