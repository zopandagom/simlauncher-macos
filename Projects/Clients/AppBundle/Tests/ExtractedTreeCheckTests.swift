import AppBundleInterface
import Foundation
import Testing
@testable import AppBundleImpl

/// 임시 폴더의 `contents/` 에 푼 결과를 직접 만들어 검사한다. 테스트마다 폴더를 지운다.
struct ExtractedTreeCheckTests {
  private static func check(_ build: (URL) throws -> Void) throws -> Result<URL, AppBundleError> {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let contents = directory.url.appending(path: "contents", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: false)
    try build(contents)
    do throws(AppBundleError) {
      return try .success(ExtractedTreeCheck.check(contents: contents))
    } catch {
      return .failure(error)
    }
  }

  private static func error(_ build: (URL) throws -> Void) throws -> AppBundleError? {
    if case let .failure(error) = try self.check(build) {
      return error
    }
    return nil
  }

  @Test("정상 .app 과 프레임워크 상대 링크는 통과하고, 맨 위 .app 의 실제 경로를 돌려준다")
  func validTree() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let contents = directory.url.appending(path: "contents", directoryHint: .isDirectory)
    try FileTree.app(contents)
    try FileTree.file(contents, "Sample.app/Frameworks/F.framework/Versions/A/F")
    try FileTree.link(contents, "Sample.app/Frameworks/F.framework/Versions/Current", to: "A")
    try FileTree.link(contents, "Sample.app/Frameworks/F.framework/F", to: "Versions/Current/F")
    try FileTree.link(contents, "Sample.app/self", to: ".")

    // 링크를 거친 경로를 넘겨도 실제 경로를 돌려준다.
    try FileTree.link(directory.url, "alias", to: "contents")
    let app = try ExtractedTreeCheck.check(contents: directory.url.appending(path: "alias"))

    let expected = try #require(RealPath.of(contents.appending(path: "Sample.app")))
    #expect(app.path(percentEncoded: false).hasPrefix(expected))
    #expect(RealPath.of(app) == expected)
    #expect(app.hasDirectoryPath)
  }

  @Test(".app 안 링크가 .app 밖·대상 없음·루프면 unsafe")
  func unsafeLinksInsideApp() throws {
    let targets: [[(String, String)]] = [
      [("Sample.app/up", "../..")],
      [("Sample.app/up", "..")],
      [("Sample.app/root", "/")],
      [("Sample.app/x", "y/.."), ("Sample.app/y", ".")],
      [("Sample.app/dangling", "nowhere")],
      [("Sample.app/a", "b"), ("Sample.app/b", "a")],
      [("Sample.app/sibling", "../README")],
    ]
    for links in targets {
      let error = try Self.error { contents in
        try FileTree.app(contents)
        try FileTree.file(contents, "README")
        for (path, target) in links {
          try FileTree.link(contents, path, to: target)
        }
      }
      #expect(error == .zipUnsafeEntry, "\(links)")
    }
  }

  @Test("맨 위 다른 항목 안의 링크는 contents 안이면 통과, 밖이면 unsafe")
  func linksOutsideApp() throws {
    let inside = try Self.error { contents in
      try FileTree.app(contents)
      try FileTree.link(contents, "Docs/readme", to: "../Sample.app/Info.plist")
    }
    let outside = try Self.error { contents in
      try FileTree.app(contents)
      try FileTree.link(contents, "Docs/escape", to: "../..")
    }
    let metadata = try Self.error { contents in
      try FileTree.app(contents)
      try FileTree.link(contents, "__MACOSX/escape", to: "/etc")
    }

    #expect(inside == nil)
    #expect(outside == .zipUnsafeEntry)
    #expect(metadata == .zipUnsafeEntry)
  }

  @Test("맨 위 .app 이 링크면 unsafe (안쪽 폴더를 가리켜도)")
  func topLevelAppLink() throws {
    let error = try Self.error { contents in
      try FileTree.app(contents, "Real")
      try FileTree.link(contents, "Sample.app", to: "Real")
    }

    #expect(error == .zipUnsafeEntry)
  }

  @Test(".app 폴더가 0개(파일 X.app·이름이 정확히 .app·하위에만)면 withoutApp, 2개면 withMultipleApps")
  func appCount() throws {
    let none = try Self.error { contents in
      try FileTree.file(contents, "X.app")
      try FileTree.directory(contents, ".app")
      try FileTree.app(contents.appending(path: "Payload"))
    }
    let two = try Self.error { contents in
      try FileTree.app(contents)
      try FileTree.app(contents, "Other.APP")
    }
    let empty = try Self.error { _ in }

    #expect(none == .zipWithoutApp)
    #expect(two == .zipWithMultipleApps)
    #expect(empty == .zipWithoutApp)
  }

  @Test("__MACOSX·._x·README·dSYM 은 무시한다")
  func ignoresOtherTopLevelItems() throws {
    let error = try Self.error { contents in
      try FileTree.app(contents)
      try FileTree.app(contents.appending(path: "__MACOSX"))
      try FileTree.directory(contents, "._Other.app")
      try FileTree.file(contents, "README.txt")
      try FileTree.directory(contents, "Sample.app.dSYM/Contents")
    }

    #expect(error == nil)
  }

  @Test("읽을 수 없는 폴더(.app 안 0o111)가 있으면 zipUnreadable")
  func unreadableDirectory() throws {
    let error = try Self.error { contents in
      try FileTree.app(contents)
      try FileTree.file(contents, "Sample.app/locked/inner/f")
      try FileTree.directory(contents, "Sample.app/locked", mode: 0o111)
    }

    #expect(error == .zipUnreadable)
  }

  @Test("contents 가 없으면 zipUnreadable")
  func missingContents() {
    #expect(throws: AppBundleError.zipUnreadable) {
      try ExtractedTreeCheck.check(contents: URL(filePath: "/nonexistent-\(UUID().uuidString)"))
    }
  }
}
