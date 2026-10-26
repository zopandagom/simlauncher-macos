import Core
import Foundation
import Testing
import WorkspaceInterface
@testable import WorkspaceImpl

/// 동영상 폴더(`~/Movies` 자리의 임시 폴더)에 녹화 파일을 예약·삭제하는 동작. 준비 함수는 `WorkspaceClientImplTests` 것을 쓴다.
struct WorkspaceClientImplRecordingTests {
  @Test("동영상 폴더에 SimLauncher 가 없으면 만들고, 그 안에 번호 없는 이름의 빈 .mov 를 예약한다")
  func reservesRecordingInNewFolder() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let name = Recording.name()

    let file = try await WorkspaceClientImplTests.client(tmp).reserveRecordingFile(name)

    #expect(file.lastPathComponent == name.fileName(attempt: 1))
    #expect(file.pathExtension == "mov")
    #expect(file.parentPath == tmp.moviesFolder.plainPath)
    #expect(try WorkspaceClientImplTests.size(file) == 0)
    // 사진 폴더의 저장 폴더는 만들지 않는다.
    #expect(!FileManager.default.fileExists(atPath: tmp.folder.plainPath))
  }

  @Test("같은 녹화 이름이 있으면 다음 번호로 예약하고, 이미 있는 파일은 바꾸지 않는다")
  func recordingNextNumber() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let client = WorkspaceClientImplTests.client(tmp)
    let name = Recording.name()

    let first = try await client.reserveRecordingFile(name)
    try Data("old".utf8).write(to: first)
    let second = try await client.reserveRecordingFile(name)

    #expect(second.lastPathComponent == name.fileName(attempt: 2))
    #expect(try String(contentsOf: first, encoding: .utf8) == "old")
  }

  @Test("동영상 폴더를 찾지 못하면 녹화 예약은 folderUnavailable 이고 스크린샷 예약은 된다")
  func noMoviesDirectory() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let client = WorkspaceClientImpl(picturesDirectory: tmp.url, moviesDirectory: nil, reveal: { _ in })

    await #expect(throws: WorkspaceError.folderUnavailable) {
      try await client.reserveRecordingFile(Recording.name())
    }
    _ = try await client.reserveScreenshotFile(Screenshot.name())
  }

  @Test("동영상 폴더의 SimLauncher 자리에 파일이 있으면 folderUnavailable")
  func fileInPlaceOfMoviesFolder() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try FileManager.default.createDirectory(at: tmp.movies, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: tmp.movies.appending(path: "SimLauncher"))

    await #expect(throws: WorkspaceError.folderUnavailable) {
      try await WorkspaceClientImplTests.client(tmp).reserveRecordingFile(Recording.name())
    }
  }

  @Test("동영상 폴더 안의 빈 예약 파일을 지운다")
  func removesReservedRecording() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let client = WorkspaceClientImplTests.client(tmp)
    let file = try await client.reserveRecordingFile(Recording.name())

    await client.removeReservedFile(file)

    #expect(!FileManager.default.fileExists(atPath: file.plainPath))
  }

  @Test("사진·동영상 폴더의 저장 폴더 바로 안이 아닌 빈 파일은 지우지 않는다")
  func keepsEmptyFilesOutsideFolders() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let client = WorkspaceClientImplTests.client(tmp)
    _ = try await client.reserveRecordingFile(Recording.name())
    let inMovies = tmp.movies.appending(path: "outside.mov")
    let nested = tmp.moviesFolder.appending(path: "sub/inner.mov")
    let elsewhere = tmp.url.appending(path: "Other/SimLauncher/a.mov")
    for file in [inMovies, nested, elsewhere] {
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data().write(to: file)
    }

    for file in [inMovies, nested, elsewhere, tmp.moviesFolder.appending(path: "../outside.mov")] {
      await client.removeReservedFile(file)
    }

    for file in [inMovies, nested, elsewhere] {
      #expect(FileManager.default.fileExists(atPath: file.plainPath))
    }
  }
}
