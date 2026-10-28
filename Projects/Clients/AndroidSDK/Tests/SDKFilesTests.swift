import AndroidSDKInterface
import Core
import DownloadInterface
import Foundation
import Testing
@testable import AndroidSDKImpl

struct SDKFilesTests {
  @Test("source.properties 의 Pkg.Revision (키 앞뒤 공백 무시, 처음 것), 없거나 형식이 틀리면 nil")
  func revisionProperties() {
    #expect(SDKFiles.revision(properties: "Pkg.UserSrc=false\nPkg.Revision=37.0.1\n") == AndroidRevision(
      major: 37,
      minor: 0,
      micro: 1
    ))
    #expect(SDKFiles.revision(properties: " Pkg.Revision = 7\r\nPkg.Revision=8") == AndroidRevision(major: 7))
    #expect(SDKFiles.revision(properties: "Pkg.Path=emulator") == nil)
    #expect(SDKFiles.revision(properties: "Pkg.Revision=37.0.0 rc1") == nil)
  }

  @Test("source.properties 파일: 일반 파일만, 64 KiB 를 넘으면 nil")
  func revisionFile() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    try FileTree.file(directory.url, "ok", contents: "Pkg.Revision=1.2.3")
    try FileTree.file(
      directory.url,
      "big",
      contents: "Pkg.Revision=1\n" + String(repeating: "#", count: SDKFiles.sourcePropertiesLimit)
    )
    try FileTree.directory(directory.url, "dir")

    #expect(SDKFiles.revision(sourceProperties: directory.url.appending(path: "ok").path(percentEncoded: false))
      == AndroidRevision(major: 1, minor: 2, micro: 3))
    #expect(SDKFiles
      .revision(sourceProperties: directory.url.appending(path: "big").path(percentEncoded: false)) == nil)
    #expect(SDKFiles
      .revision(sourceProperties: directory.url.appending(path: "dir").path(percentEncoded: false)) == nil)
    #expect(SDKFiles
      .revision(sourceProperties: directory.url.appending(path: "none").path(percentEncoded: false)) == nil)
  }

  @Test("파일 종류: 없음·폴더·실행 파일·일반 파일·깨진 링크(file)·읽을 수 없는 폴더")
  func kinds() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let base = directory.url
    try FileTree.directory(base, "dir")
    try FileTree.directory(base, "locked", mode: 0o000)
    try FileTree.file(base, "exec", mode: 0o755)
    try FileTree.file(base, "plain", mode: 0o644)
    try FileTree.link(base, "broken", to: "nowhere")
    func kind(_ name: String) -> AndroidFileKind {
      SDKFiles.kind(base.appending(path: name).path(percentEncoded: false))
    }

    #expect(kind("none") == .absent)
    #expect(kind("dir") == .directory)
    #expect(kind("locked") == .unreadable)
    #expect(kind("exec") == .executableFile)
    #expect(kind("plain") == .file)
    #expect(kind("broken") == .file)
    #expect(kind("plain/child") == .absent)
  }

  @Test("가장 가까운 있는 조상")
  func nearestAncestor() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let deep = directory.child("a/b/c")

    #expect(SDKFiles.nearestExistingAncestor(of: deep).path(percentEncoded: false)
      .hasSuffix(directory.url.lastPathComponent + "/"))
    #expect(SDKFiles.existingFolder(for: directory.url) == directory.url)
  }

  @Test("받기 실패 옮기기: 같은 이름의 원인, cancelled 는 nil")
  func downloadFailureMapping() {
    let cases: [(DownloadError, AndroidDownloadFailure?)] = [
      (.insecureRedirect, .insecureRedirect), (.httpStatus(404), .httpStatus(404)), (.offline, .offline),
      (.hostNotFound, .hostNotFound), (.cannotConnect, .cannotConnect), (.timedOut, .timedOut),
      (.connectionLost, .connectionLost), (.secureConnectionFailed, .secureConnectionFailed),
      (.insufficientDiskSpace, .insufficientDiskSpace), (.tooLarge, .tooLarge),
      (.storageUnavailable, .storageUnavailable), (.failed, .failed), (.cancelled, nil),
    ]
    for (error, expected) in cases {
      #expect(DownloadFailureMapping.failure(error) == expected)
    }
  }

  @Test("저장소 주소는 Google 고정 주소이고, archive 기준 폴더는 XML 이 있는 폴더")
  func endpoints() {
    let google = RepositoryEndpoints.google
    #expect(google.repository.url.absoluteString == "https://dl.google.com/android/repository/repository2-3.xml")
    #expect(google.repositoryBase.url.absoluteString == "https://dl.google.com/android/repository/")
    #expect(google.systemImages.url.absoluteString
      == "https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-3.xml")
    #expect(google.systemImagesBase.url
      .absoluteString == "https://dl.google.com/android/repository/sys-img/google_apis/")
  }
}
