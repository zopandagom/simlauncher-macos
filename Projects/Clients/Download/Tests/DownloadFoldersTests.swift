import Core
import DownloadInterface
import Foundation
import Testing
@testable import DownloadImpl

/// `removeDownloaded`·`removeLeftoverDownloads`: 형식에 맞는 폴더만 지운다.
struct DownloadFoldersTests {
  @Test("removeDownloaded 는 받은 폴더를 지우고, 두 번 불러도 아무 일 없다")
  func removeDownloaded() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let url = StubURLProtocol.registerDownload(
      .respond(status: 200, headers: ["Content-Length": "1"], chunks: [Data("a".utf8)], finish: true)
    )
    let client = tmp.client()
    let downloaded = try await client.download(url) { _ in }

    await client.removeDownloaded(downloaded)
    await client.removeDownloaded(downloaded)

    #expect(tmp.names.isEmpty)
    StubURLProtocol.expectNoUnregisteredRequests()
  }

  @Test("removeDownloaded 는 형식에 맞지 않는 폴더(다른 이름·임시 폴더 밖·링크)를 지우지 않는다")
  func removeDownloadedKeepsOthers() async throws {
    let tmp = try TemporaryDirectory()
    let outside = try TemporaryDirectory()
    defer {
      tmp.remove()
      outside.remove()
    }
    let manager = FileManager.default
    let otherName = tmp.url.appending(path: "SimLauncher-Download-not-uuid", directoryHint: .isDirectory)
    let outsideFolder = outside.url.appending(path: DownloadFolders.newName(), directoryHint: .isDirectory)
    let link = tmp.url.appending(path: DownloadFolders.newName(), directoryHint: .isDirectory)
    try manager.createDirectory(at: otherName, withIntermediateDirectories: false)
    try manager.createDirectory(at: outsideFolder, withIntermediateDirectories: false)
    try manager.createSymbolicLink(at: link, withDestinationURL: outsideFolder)
    let client = tmp.client()

    for folder in [otherName, outsideFolder, link] {
      let file = folder.appending(path: "download", directoryHint: .notDirectory)
      await client.removeDownloaded(DownloadedFile(file: file, folder: folder, byteCount: 0, mimeType: nil))
    }

    #expect(manager.fileExists(atPath: otherName.path(percentEncoded: false)))
    #expect(manager.fileExists(atPath: outsideFolder.path(percentEncoded: false)))
    #expect(mode(link) != nil)
  }

  @Test("removeLeftoverDownloads 는 앞선 실행의 폴더만 지우고, 받는 중 폴더·UUID 아닌 이름·링크·파일은 남긴다")
  func removeLeftovers() async throws {
    let tmp = try TemporaryDirectory()
    let outside = try TemporaryDirectory()
    defer {
      tmp.remove()
      outside.remove()
    }
    let manager = FileManager.default
    let leftover = tmp.url.appending(path: DownloadFolders.newName(), directoryHint: .isDirectory)
    let otherName = tmp.url.appending(path: "SimLauncher-Download-not-uuid", directoryHint: .isDirectory)
    let link = tmp.url.appending(path: DownloadFolders.newName(), directoryHint: .isDirectory)
    let file = tmp.url.appending(path: DownloadFolders.newName(), directoryHint: .notDirectory)
    try manager.createDirectory(at: leftover, withIntermediateDirectories: false)
    try Data("x".utf8).write(to: leftover.appending(path: "download"))
    try manager.createDirectory(at: otherName, withIntermediateDirectories: false)
    try manager.createSymbolicLink(at: link, withDestinationURL: outside.url)
    try Data("x".utf8).write(to: file)
    // 끝내지 않는 받기: 첫 진행 값이 오면 폴더가 만들어져 있다.
    let url = StubURLProtocol.registerDownload(
      .respond(status: 200, headers: ["Content-Length": "3000"], chunks: [Data(count: 1000)], finish: false)
    )
    let client = tmp.client()
    let started = ProgressLog()
    let task = Task { try await client.download(url) { started.append($0) } }
    try await waitUntil { !started.values.isEmpty }
    let before = Set(tmp.names)

    await client.removeLeftoverDownloads()

    let after = Set(tmp.names)
    #expect(before.subtracting(after) == [leftover.lastPathComponent])
    #expect(after.contains(otherName.lastPathComponent))
    #expect(after.contains(link.lastPathComponent))
    #expect(after.contains(file.lastPathComponent))
    #expect(manager.fileExists(atPath: outside.url.path(percentEncoded: false)))
    // 받는 중 폴더(위 네 개 밖의 하나)가 남아 있다.
    #expect(after.count == 4)
    task.cancel()
    await #expect(throws: DownloadError.cancelled) { try await task.value }
    #expect(tmp.names.count == 3)
    StubURLProtocol.expectNoUnregisteredRequests()
  }
}
