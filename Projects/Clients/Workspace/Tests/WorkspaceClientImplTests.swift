import Core
import Foundation
import Testing
import WorkspaceInterface
@testable import WorkspaceImpl

/// 실제 파일 시스템을 쓰지만 사진 폴더 자리에 임시 폴더를 주입해 `~/Pictures` 는 건드리지 않는다. Finder 는 열지 않는다(기록 클로저).
struct WorkspaceClientImplTests {
  static func client(_ tmp: TemporaryDirectory, recorder: RevealRecorder = RevealRecorder()) -> WorkspaceClientImpl {
    WorkspaceClientImpl(picturesDirectory: tmp.url, reveal: { recorder.record($0) })
  }

  static func size(_ url: URL) throws -> Int {
    try #require(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
  }

  @Test("저장 폴더가 없으면 만들고, 그 안에 번호 없는 이름의 빈 파일을 예약한다")
  func reservesInNewFolder() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let name = Screenshot.name()

    let file = try await Self.client(tmp).reserveScreenshotFile(name)

    #expect(file.lastPathComponent == name.fileName(attempt: 1))
    #expect(file.parentPath == tmp.folder.plainPath)
    #expect(FileManager.default.fileExists(atPath: file.plainPath))
    #expect(try Self.size(file) == 0)
  }

  @Test("같은 이름이 있으면 다음 번호로 예약하고, 이미 있는 파일은 바꾸지 않는다")
  func nextNumber() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let client = Self.client(tmp)
    let name = Screenshot.name()

    let first = try await client.reserveScreenshotFile(name)
    try Data("old".utf8).write(to: first)
    let second = try await client.reserveScreenshotFile(name)

    #expect(second.lastPathComponent == name.fileName(attempt: 2))
    #expect(try String(contentsOf: first, encoding: .utf8) == "old")

    let third = try await client.reserveScreenshotFile(name)
    #expect(third.lastPathComponent == name.fileName(attempt: 3))
    let fourth = try await client.reserveScreenshotFile(name)
    #expect(fourth.lastPathComponent == name.fileName(attempt: 4))
  }

  @Test("1~99 가 모두 있으면 fileNameUnavailable")
  func allNamesTaken() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let name = Screenshot.name()
    try FileManager.default.createDirectory(at: tmp.folder, withIntermediateDirectories: true)
    for attempt in 1 ... ScreenshotFileName.maxAttempts {
      let fileName = try #require(name.fileName(attempt: attempt))
      try Data("x".utf8).write(to: tmp.folder.appending(path: fileName))
    }

    await #expect(throws: WorkspaceError.fileNameUnavailable) {
      try await Self.client(tmp).reserveScreenshotFile(name)
    }
  }

  @Test("같은 이름의 대상 없는 심볼릭 링크가 있으면 다음 번호이고 링크 대상을 만들지 않는다")
  func danglingLinkWithSameName() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let name = Screenshot.name()
    let target = tmp.url.appending(path: "missing.png")
    try FileManager.default.createDirectory(at: tmp.folder, withIntermediateDirectories: true)
    let link = try tmp.folder.appending(path: #require(name.fileName(attempt: 1)))
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    let file = try await Self.client(tmp).reserveScreenshotFile(name)

    #expect(file.lastPathComponent == name.fileName(attempt: 2))
    #expect(!FileManager.default.fileExists(atPath: target.plainPath))
  }

  @Test("SimLauncher 자리에 파일이 있으면 folderUnavailable")
  func fileInPlaceOfFolder() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try Data("x".utf8).write(to: tmp.url.appending(path: "SimLauncher"))

    await #expect(throws: WorkspaceError.folderUnavailable) {
      try await Self.client(tmp).reserveScreenshotFile(Screenshot.name())
    }
  }

  @Test("저장 폴더에 쓸 수 없으면 folderUnavailable")
  func readOnlyFolder() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try FileManager.default.createDirectory(at: tmp.folder, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tmp.folder.plainPath)
    defer { TemporaryDirectory.restoreOwnerPermissions(tmp.folder) }

    await #expect(throws: WorkspaceError.folderUnavailable) {
      try await Self.client(tmp).reserveScreenshotFile(Screenshot.name())
    }
  }

  @Test("사진 폴더를 찾지 못하면 folderUnavailable")
  func noPicturesDirectory() async {
    let client = WorkspaceClientImpl(picturesDirectory: nil, reveal: { _ in })

    await #expect(throws: WorkspaceError.folderUnavailable) {
      try await client.reserveScreenshotFile(Screenshot.name())
    }
  }

  @Test("SimLauncher 가 대상 없는 링크이거나 파일을 가리키는 링크면 folderUnavailable", arguments: [false, true])
  func linkNotToDirectory(targetExists: Bool) async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let target = tmp.url.appending(path: "target")
    if targetExists {
      try Data("x".utf8).write(to: target)
    }
    try FileManager.default.createSymbolicLink(at: tmp.url.appending(path: "SimLauncher"), withDestinationURL: target)

    await #expect(throws: WorkspaceError.folderUnavailable) {
      try await Self.client(tmp).reserveScreenshotFile(Screenshot.name())
    }
    #expect(FileManager.default.fileExists(atPath: target.plainPath) == targetExists)
  }

  @Test("SimLauncher 가 디렉터리를 가리키는 링크면 따라가 그 폴더에 만들고, 돌려준 URL 로 지운다")
  func linkToDirectory() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let target = tmp.url.appending(path: "Elsewhere", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: tmp.url.appending(path: "SimLauncher"), withDestinationURL: target)
    let client = Self.client(tmp)

    let file = try await client.reserveScreenshotFile(Screenshot.name())

    #expect(file.parentPath == tmp.folder.plainPath)
    let inTarget = target.appending(path: file.lastPathComponent)
    #expect(FileManager.default.fileExists(atPath: inTarget.plainPath))

    await client.removeReservedFile(file)
    #expect(!FileManager.default.fileExists(atPath: inTarget.plainPath))
  }

  @Test("예약한 파일을 지운다")
  func removesReserved() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let client = Self.client(tmp)
    let file = try await client.reserveScreenshotFile(Screenshot.name())

    await client.removeReservedFile(file)

    #expect(!FileManager.default.fileExists(atPath: file.plainPath))
  }

  @Test("저장 폴더 바로 안이 아닌 파일·폴더는 지우지 않는다")
  func keepsOutsideFiles() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let client = Self.client(tmp)
    _ = try await client.reserveScreenshotFile(Screenshot.name())
    let outside = tmp.url.appending(path: "outside.png")
    let nested = tmp.folder.appending(path: "sub/inner.png")
    let directory = tmp.folder.appending(path: "folder.png", directoryHint: .isDirectory)
    try Data("x".utf8).write(to: outside)
    try FileManager.default.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: nested)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    await client.removeReservedFile(outside)
    await client.removeReservedFile(tmp.folder.appending(path: "../outside.png"))
    await client.removeReservedFile(nested)
    await client.removeReservedFile(tmp.folder)
    await client.removeReservedFile(directory)

    #expect(FileManager.default.fileExists(atPath: outside.plainPath))
    #expect(FileManager.default.fileExists(atPath: nested.plainPath))
    #expect(FileManager.default.fileExists(atPath: directory.plainPath))
  }

  @Test("있는 파일은 Finder 에서 한 번 선택해 보인다")
  func revealsExisting() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let recorder = RevealRecorder()
    let client = Self.client(tmp, recorder: recorder)
    let file = try await client.reserveScreenshotFile(Screenshot.name())

    try await client.revealInFinder(file)

    #expect(recorder.received == [[file]])
  }

  @Test("없는 파일은 Finder 를 열지 않고 fileNotFound")
  func revealMissing() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let recorder = RevealRecorder()
    let client = Self.client(tmp, recorder: recorder)

    await #expect(throws: WorkspaceError.fileNotFound) {
      try await client.revealInFinder(tmp.folder.appending(path: "missing.png"))
    }
    #expect(recorder.received.isEmpty)
  }

  @Test("부모 확인: 저장 폴더 바로 안의 이름 한 단계만 통과한다")
  func directChild() throws {
    let folder = URL(filePath: "/p/SimLauncher/", directoryHint: .isDirectory)
    #expect(WorkspaceClientImpl.isDirectChild(URL(filePath: "/p/SimLauncher/a.png"), of: folder))
    #expect(WorkspaceClientImpl.isDirectChild(URL(filePath: "/p/SimLauncher/./a.png"), of: folder))
    #expect(!WorkspaceClientImpl.isDirectChild(URL(filePath: "/p/SimLauncher/../a.png"), of: folder))
    #expect(!WorkspaceClientImpl.isDirectChild(URL(filePath: "/p/SimLauncher/x/a.png"), of: folder))
    #expect(!WorkspaceClientImpl.isDirectChild(URL(filePath: "/p/a.png"), of: folder))
    #expect(!WorkspaceClientImpl.isDirectChild(folder, of: folder))
    #expect(try !WorkspaceClientImpl.isDirectChild(#require(URL(string: "https://p/SimLauncher/a.png")), of: folder))
  }
}
