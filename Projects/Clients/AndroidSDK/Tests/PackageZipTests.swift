import Foundation
import Testing
@testable import AndroidSDKImpl

/// zipinfo 목록 해석·풀기 전 검사·푼 뒤 트리 검사.
struct PackageZipTests {
  static func listing(_ lines: [String]) -> PackageZipListing {
    PackageZipListing.parse(ZipinfoText.listing(lines))!
  }

  static func file(_ name: String, size: Int64 = 1) -> String {
    "-rw-r--r--  3.0 unx \(size) bx defN 20251014.120000 \(name)"
  }

  static func folder(_ name: String) -> String {
    "drwxr-xr-x  3.0 unx 0 bx stor 20251014.120000 \(name)"
  }

  static func link(_ name: String) -> String {
    "lrwxr-xr-x  3.0 unx 5 bx stor 20251014.120000 \(name)"
  }

  static func check(_ lines: [String]) -> PackageArchiveFailure? {
    do throws(PackageArchiveFailure) {
      try PackageZipListingCheck.check(self.listing(lines))
      return nil
    } catch {
      return error
    }
  }

  // MARK: - 해석

  @Test("Zip64 항목 크기 열(5498732544)을 읽고 크기 합을 낸다")
  func parsesZip64() throws {
    let listing = try #require(PackageZipListing.parse(PackageSpec(.systemImage).zipinfo))

    #expect(listing.declaredCount == 2)
    #expect(listing.entries.map(\.name) == ["arm64-v8a/system.img", "arm64-v8a/source.properties"])
    #expect(listing.entries.first?.size == 5_498_732_544)
    #expect(listing.declaredTotalBytes == 5_498_732_664)
  }

  @Test("종류: d → 폴더, 끝 / → 폴더, l → 링크, - → 파일. 넘치는 크기 합은 Int64.max")
  func kinds() {
    let listing = Self.listing([
      Self.folder("a/"), Self.file("a/b/"), Self.link("a/l"), Self.file("a/f", size: .max), Self.file("a/g", size: 1),
    ])
    #expect(listing.entries.map(\.kind) == [.directory, .directory, .symlink, .file, .file])
    #expect(listing.declaredTotalBytes == .max)
  }

  @Test("헤더가 다르거나 줄이 모자라거나 항목 줄을 읽지 못하면 nil")
  func parseFailures() {
    #expect(PackageZipListing.parse("garbage") == nil)
    #expect(PackageZipListing
      .parse("Archive:  x\nZip file size: 1 bytes, number of entries: 2\n\(Self.file("a/b"))") == nil)
    #expect(PackageZipListing.parse("Archive:  x\nZip file size: 1 bytes, number of entries: 1\nwarning: extra") == nil)
  }

  // MARK: - 풀기 전 검사

  @Test("맨 위 폴더 하나면 통과: 폴더 항목 없이 platform-tools/adb 만 있어도, 폴더 항목만 있어도, 안쪽 링크도")
  func passes() {
    #expect(Self.check([Self.file("platform-tools/adb"), Self.file("platform-tools/lib/x")]) == nil)
    #expect(Self.check([Self.folder("emulator/")]) == nil)
    #expect(Self
      .check([Self.folder("arm64-v8a/"), Self.file("./arm64-v8a/system.img"), Self.link("arm64-v8a/l")]) == nil)
  }

  @Test("항목이 없으면 unreadable")
  func empty() {
    #expect(throws: PackageArchiveFailure.unreadable) {
      try PackageZipListingCheck.check(PackageZipListing(declaredCount: 0, entries: []))
    }
  }

  @Test("경로 탈출(/ 시작·.. 구성 요소)·빈 이름 → unsafe")
  func escapes() {
    #expect(Self.check([Self.file("platform-tools/adb"), Self.file("/etc/x")]) == .unsafe)
    #expect(Self.check([Self.file("platform-tools/../../x")]) == .unsafe)
    #expect(Self.check([Self.file("../x")]) == .unsafe)
    #expect(Self.check([Self.file("./")]) == .unsafe)
  }

  @Test("맨 위 항목이 둘 이상(__MACOSX 포함) → unsafe")
  func multipleTops() {
    #expect(Self.check([Self.file("platform-tools/adb"), Self.file("emulator/emulator")]) == .unsafe)
    #expect(Self.check([Self.file("platform-tools/adb"), Self.file("__MACOSX/._adb")]) == .unsafe)
    #expect(Self.check([Self.file("platform-tools/adb"), Self.file("README")]) == .unsafe)
  }

  @Test("맨 위가 파일 하나뿐이거나 맨 위 이름이 링크 → unsafe")
  func topNotFolder() {
    #expect(Self.check([Self.file("platform-tools")]) == .unsafe)
    #expect(Self.check([Self.link("platform-tools"), Self.file("platform-tools/adb")]) == .unsafe)
  }

  @Test("링크 항목의 경로가 다른 항목 경로의 앞부분이면 unsafe (링크를 만든 뒤 그 아래에 쓰는 zip)")
  func writesThroughLink() {
    #expect(Self.check([Self.link("platform-tools/lib"), Self.file("platform-tools/lib/evil")]) == .unsafe)
    #expect(Self.check([Self.link("platform-tools/lib"), Self.file("platform-tools/library")]) == nil)
  }

  // MARK: - 푼 뒤 트리 검사

  @Test("맨 위 폴더 하나와 그 안을 가리키는 링크는 통과, 실제 경로를 돌려준다 (__MACOSX 무시)")
  func treePasses() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let contents = directory.child("contents")
    try FileTree.file(contents, "emulator/lib/a")
    try FileTree.link(contents, "emulator/current", to: "lib")
    try FileTree.directory(contents, "__MACOSX")

    let top = try PackageTreeCheck.check(contents: contents)
    #expect(top.path(percentEncoded: false) == contents.appending(path: "emulator").path(percentEncoded: false) + "/")
  }

  @Test("트리: 밖을 가리키는 링크·깨진 링크·맨 위 링크·맨 위 둘 → unsafe, 빈 트리·맨 위 파일 → unreadable")
  func treeFailures() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    func check(_ name: String, _ build: (URL) throws -> Void) throws -> PackageArchiveFailure? {
      let contents = directory.child(name)
      try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
      try build(contents)
      do throws(PackageArchiveFailure) {
        _ = try PackageTreeCheck.check(contents: contents)
        return nil
      } catch {
        return error
      }
    }

    #expect(try check("outside") { try FileTree.link($0, "top/x", to: "../..") } == .unsafe)
    #expect(try check("broken") { try FileTree.link($0, "top/x", to: "nowhere") } == .unsafe)
    #expect(try check("toplink") { try FileTree.link($0, "top", to: "/tmp") } == .unsafe)
    #expect(try check("two") {
      try FileTree.directory($0, "a")
      try FileTree.directory($0, "b")
    } == .unsafe)
    #expect(try check("empty") { _ in } == .unreadable)
    #expect(try check("file") { try FileTree.file($0, "top") } == .unreadable)
  }
}
