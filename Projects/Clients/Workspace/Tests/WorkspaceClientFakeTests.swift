import Core
import Foundation
import Testing
import WorkspaceInterface
import WorkspaceTesting

struct WorkspaceClientFakeTests {
  static func file(_ name: ScreenshotFileName, attempt: Int) throws -> URL {
    let fileName = try #require(name.fileName(attempt: attempt))
    return WorkspaceClientFake.folder.appending(path: fileName, directoryHint: .notDirectory)
  }

  @Test("호출을 순서대로 기록하고, 예약은 가짜 저장 폴더 아래 번호 없는 이름이다")
  func recordsCalls() async throws {
    let fake = WorkspaceClientFake()
    let name = Screenshot.name()

    let file = try await fake.reserveScreenshotFile(name)
    try await fake.revealInFinder(file)
    await fake.removeReservedFile(file)

    #expect(try file == (Self.file(name, attempt: 1)))
    #expect(fake.calls == [.reserveScreenshotFile(stem: name.stem), .revealInFinder(file), .removeReservedFile(file)])
    #expect(fake.reservedFiles.isEmpty)
  }

  @Test("같은 이름을 둘 예약하면 두 번째는 2, 첫째를 지운 뒤 다시 예약하면 번호 없음")
  func numbering() async throws {
    let fake = WorkspaceClientFake()
    let name = Screenshot.name()

    let first = try await fake.reserveScreenshotFile(name)
    let second = try await fake.reserveScreenshotFile(name)
    #expect(try second == (Self.file(name, attempt: 2)))

    await fake.removeReservedFile(first)
    let again = try await fake.reserveScreenshotFile(name)
    #expect(again == first)
    #expect(fake.reservedFiles == [second, first])

    // 다른 이름은 번호 없이.
    let other = try await fake.reserveScreenshotFile(Screenshot.name("iPad"))
    #expect(other.lastPathComponent == Screenshot.name("iPad").fileName(attempt: 1))
  }

  @Test("99 까지 모두 예약돼 있으면 fileNameUnavailable")
  func allNamesTaken() async throws {
    let fake = WorkspaceClientFake()
    let name = Screenshot.name()
    for _ in 1 ... ScreenshotFileName.maxAttempts {
      _ = try await fake.reserveScreenshotFile(name)
    }

    await #expect(throws: WorkspaceError.fileNameUnavailable) {
      try await fake.reserveScreenshotFile(name)
    }
    #expect(fake.reservedFiles.count == ScreenshotFileName.maxAttempts)
  }

  @Test("설정한 오류로 실패하고 기록은 남는다. nil 로 되돌리면 성공한다")
  func errors() async throws {
    let fake = WorkspaceClientFake()
    let name = Screenshot.name()
    fake.setReserveError(.folderUnavailable)
    fake.setRevealError(.fileNotFound)

    await #expect(throws: WorkspaceError.folderUnavailable) {
      try await fake.reserveScreenshotFile(name)
    }
    let file = try Self.file(name, attempt: 1)
    await #expect(throws: WorkspaceError.fileNotFound) {
      try await fake.revealInFinder(file)
    }
    #expect(fake.calls == [.reserveScreenshotFile(stem: name.stem), .revealInFinder(file)])
    #expect(fake.reservedFiles.isEmpty)

    fake.setReserveError(nil)
    fake.setRevealError(nil)
    let reserved = try await fake.reserveScreenshotFile(name)
    try await fake.revealInFinder(reserved)
  }

  @Test("예약 목록에 없는 파일도 보이기는 성공한다")
  func revealUnreserved() async throws {
    let fake = WorkspaceClientFake()
    let file = URL(filePath: "/elsewhere/a.png")

    try await fake.revealInFinder(file)

    #expect(fake.calls == [.revealInFinder(file)])
  }

  @Test("멈춘 예약은 기록만 하고 resume 뒤에 끝난다")
  func suspendAndResume() async throws {
    let fake = WorkspaceClientFake()
    let name = Screenshot.name()
    fake.suspendReserves()

    let task = Task { try await fake.reserveScreenshotFile(name) }
    while fake.calls.isEmpty {
      await Task.yield()
    }
    #expect(fake.reservedFiles.isEmpty)

    fake.resumeReserves()
    let file = try await task.value
    #expect(try file == (Self.file(name, attempt: 1)))

    // resume 뒤의 예약은 멈추지 않는다.
    _ = try await fake.reserveScreenshotFile(name)
    #expect(fake.reservedFiles.count == 2)
  }

  // MARK: - 녹화

  @Test("녹화 예약은 동영상 가짜 폴더 아래 번호를 매기고 호출을 기록한다")
  func recordingReserve() async throws {
    let fake = WorkspaceClientFake()
    let name = Recording.name()

    let first = try await fake.reserveRecordingFile(name)
    let second = try await fake.reserveRecordingFile(name)
    let screenshot = try await fake.reserveScreenshotFile(Screenshot.name())

    let firstName = try #require(name.fileName(attempt: 1))
    let secondName = try #require(name.fileName(attempt: 2))
    #expect(first == WorkspaceClientFake.moviesFolder.appending(path: firstName, directoryHint: .notDirectory))
    #expect(second == WorkspaceClientFake.moviesFolder.appending(path: secondName, directoryHint: .notDirectory))
    // 스크린샷은 같은 stem 이어도 다른 폴더라 번호 없이.
    #expect(try screenshot == Self.file(Screenshot.name(), attempt: 1))
    #expect(fake.calls == [
      .reserveRecordingFile(stem: name.stem),
      .reserveRecordingFile(stem: name.stem),
      .reserveScreenshotFile(stem: Screenshot.name().stem),
    ])

    await fake.removeReservedFile(first)
    #expect(fake.reservedFiles == [second, screenshot])
  }

  @Test("설정한 예약 오류가 녹화 예약에도 적용된다")
  func recordingReserveError() async throws {
    let fake = WorkspaceClientFake()
    fake.setReserveError(.folderUnavailable)

    await #expect(throws: WorkspaceError.folderUnavailable) {
      try await fake.reserveRecordingFile(Recording.name())
    }
    #expect(fake.calls == [.reserveRecordingFile(stem: Recording.name().stem)])
    #expect(fake.reservedFiles.isEmpty)
  }

  @Test("멈춘 예약 설정이 녹화 예약도 멈춘다")
  func recordingSuspend() async throws {
    let fake = WorkspaceClientFake()
    fake.suspendReserves()

    let task = Task { try await fake.reserveRecordingFile(Recording.name()) }
    while fake.calls.isEmpty {
      await Task.yield()
    }
    #expect(fake.reservedFiles.isEmpty)

    fake.resumeReserves()
    let file = try await task.value
    #expect(fake.reservedFiles == [file])
  }
}
