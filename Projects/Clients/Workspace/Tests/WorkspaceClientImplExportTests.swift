import Foundation
import Synchronization
import Testing
import WorkspaceInterface
@testable import WorkspaceImpl

/// 로그 내보내기: 클립보드 쓰기(주입한 클로저)와 고른 파일 쓰기(임시 폴더), 쓰기 오류 매핑.
struct WorkspaceClientImplExportTests {
  /// 클립보드 클로저가 받은 글을 기록하고 정한 결과를 돌려준다.
  final class ClipboardRecorder: Sendable {
    private let texts = Mutex<[String]>([])
    let succeeds: Bool

    init(succeeds: Bool) {
      self.succeeds = succeeds
    }

    var received: [String] {
      self.texts.withLock { $0 }
    }

    func copy(_ text: String) -> Bool {
      self.texts.withLock { $0.append(text) }
      return self.succeeds
    }
  }

  private static func client(clipboard: ClipboardRecorder = ClipboardRecorder(succeeds: true)) -> WorkspaceClientImpl {
    WorkspaceClientImpl(
      picturesDirectory: nil,
      moviesDirectory: nil,
      reveal: { _ in },
      copy: { clipboard.copy($0) }
    )
  }

  /// 제어 문자(NUL·ESC·BEL·TAB·CR)와 한글·이모지를 담은 글.
  private static let text = "head\n\u{0}\u{1B}[31mred\u{7}\t\rtail 한글 👍🏽\n"

  // MARK: - 클립보드

  @Test("클립보드 쓰기는 글을 그대로 클로저에 넘긴다")
  func copyPassesTextToPasteboard() async throws {
    let clipboard = ClipboardRecorder(succeeds: true)

    try await Self.client(clipboard: clipboard).copyToClipboard(Self.text)

    #expect(clipboard.received == [Self.text])
  }

  @Test("클립보드에 쓰지 못하면 clipboardUnavailable")
  func copyFailureIsClipboardUnavailable() async {
    let clipboard = ClipboardRecorder(succeeds: false)

    await #expect(throws: WorkspaceExportError.clipboardUnavailable) {
      try await Self.client(clipboard: clipboard).copyToClipboard("a")
    }
    #expect(clipboard.received == ["a"])
  }

  // MARK: - 파일

  @Test("파일 쓰기는 BOM 없는 UTF-8 바이트 그대로다 (제어 문자 포함)")
  func writeIsExactUTF8WithoutBOM() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let file = tmp.url.appending(path: "log.txt")

    try await Self.client().writeTextFile(Self.text, to: file)

    let data = try Data(contentsOf: file)
    #expect(data == Data(Self.text.utf8))
    #expect(!data.starts(with: [0xEF, 0xBB, 0xBF]))
  }

  @Test("같은 이름의 파일은 새 글로 바꾼다 (읽기 전용 파일도), 폴더에 다른 파일이 남지 않는다")
  func writeReplacesExistingFile() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let file = tmp.url.appending(path: "log.txt")
    try Data("old old old".utf8).write(to: file)
    #expect(chmod(file.path(percentEncoded: false), 0o444) == 0)

    try await Self.client().writeTextFile("new", to: file)

    #expect(try String(contentsOf: file, encoding: .utf8) == "new")
    #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.url.path(percentEncoded: false)) == ["log.txt"])
  }

  @Test("고른 폴더가 없으면 folderNotFound")
  func writeIntoMissingFolderIsFolderNotFound() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let file = tmp.url.appending(path: "gone/log.txt")

    await #expect(throws: WorkspaceExportError.folderNotFound) {
      try await Self.client().writeTextFile("a", to: file)
    }
  }

  @Test("쓰기 권한 없는 폴더(555)면 noPermission 이고 파일이 생기지 않는다")
  func writeIntoReadOnlyFolderIsNoPermission() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let folder = tmp.url.appending(path: "locked", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    #expect(chmod(folder.path(percentEncoded: false), 0o555) == 0)
    let file = folder.appending(path: "log.txt")

    await #expect(throws: WorkspaceExportError.noPermission) {
      try await Self.client().writeTextFile("a", to: file)
    }
    #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
  }

  @Test("그 이름이 폴더이거나 파일 URL 이 아니면 writeFailed 이고 폴더는 그대로다")
  func writeOntoDirectoryIsWriteFailed() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let folder = tmp.url.appending(path: "log.txt", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    await #expect(throws: WorkspaceExportError.writeFailed) {
      try await Self.client().writeTextFile("a", to: tmp.url.appending(path: "log.txt"))
    }
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
    await #expect(throws: WorkspaceExportError.writeFailed) {
      try await Self.client().writeTextFile("a", to: #require(URL(string: "https://example.com/log.txt")))
    }
  }

  // MARK: - 오류 매핑

  /// 매핑할 오류 하나: CocoaError 코드(없으면 POSIX 도메인 오류 자체)와 밑 POSIX 코드.
  struct ErrorCase: Sendable, CustomTestStringConvertible {
    let cocoa: Int?
    let posix: Int32?
    let expected: WorkspaceExportError

    var testDescription: String {
      "Cocoa \(self.cocoa.map(String.init) ?? "-") / POSIX \(self.posix.map(String.init) ?? "-") → \(self.expected)"
    }

    var error: NSError {
      let underlying = self.posix.map { NSError(domain: NSPOSIXErrorDomain, code: Int($0)) }
      guard let cocoa = self.cocoa else {
        return underlying ?? NSError(domain: "other", code: 1)
      }
      return NSError(
        domain: NSCocoaErrorDomain,
        code: cocoa,
        userInfo: underlying.map { [NSUnderlyingErrorKey: $0] } ?? [:]
      )
    }
  }

  @Test(
    "쓰기 오류는 CocoaError 코드 먼저, 그다음 밑 POSIX 코드로 나눈다 (측정한 값과 그 밖)",
    arguments: [
      // 측정한 값 (CocoaError / 밑 POSIX).
      ErrorCase(cocoa: 513, posix: EACCES, expected: .noPermission),
      ErrorCase(cocoa: 640, posix: ENOSPC, expected: .diskFull),
      ErrorCase(cocoa: 642, posix: EROFS, expected: .readOnlyVolume),
      ErrorCase(cocoa: 4, posix: ENOENT, expected: .folderNotFound),
      ErrorCase(cocoa: 512, posix: EISDIR, expected: .writeFailed),
      // CocoaError 코드만.
      ErrorCase(cocoa: 513, posix: nil, expected: .noPermission),
      ErrorCase(cocoa: 640, posix: nil, expected: .diskFull),
      ErrorCase(cocoa: 642, posix: nil, expected: .readOnlyVolume),
      ErrorCase(cocoa: 4, posix: nil, expected: .folderNotFound),
      ErrorCase(cocoa: 512, posix: nil, expected: .writeFailed),
      // 일반 코드(512) 밑의 POSIX 코드.
      ErrorCase(cocoa: 512, posix: EACCES, expected: .noPermission),
      ErrorCase(cocoa: 512, posix: EPERM, expected: .noPermission),
      ErrorCase(cocoa: 512, posix: ENOSPC, expected: .diskFull),
      ErrorCase(cocoa: 512, posix: EDQUOT, expected: .diskFull),
      ErrorCase(cocoa: 512, posix: EROFS, expected: .readOnlyVolume),
      ErrorCase(cocoa: 512, posix: ENOENT, expected: .folderNotFound),
      // POSIX 도메인 오류 자체, 그 밖의 오류.
      ErrorCase(cocoa: nil, posix: EACCES, expected: .noPermission),
      ErrorCase(cocoa: nil, posix: EIO, expected: .writeFailed),
      ErrorCase(cocoa: nil, posix: nil, expected: .writeFailed),
    ]
  )
  func errorMapping(errorCase: ErrorCase) {
    #expect(WorkspaceClientImpl.exportError(errorCase.error) == errorCase.expected)
  }
}
