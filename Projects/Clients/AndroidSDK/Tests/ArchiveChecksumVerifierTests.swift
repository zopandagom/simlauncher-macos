import Core
import CryptoKit
import Foundation
import Testing
@testable import AndroidSDKImpl

struct ArchiveChecksumVerifierTests {
  @Test("작은 파일의 sha1·sha256 hex")
  func hex() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    try FileTree.file(directory.url, "f", contents: "abc")
    let file = directory.url.appending(path: "f")

    #expect(ArchiveChecksumVerifier.hex(of: file, algorithm: .sha1) == "a9993e364706816aba3e25717850c26c9cd0d89d")
    #expect(ArchiveChecksumVerifier.hex(of: file, algorithm: .sha256)
      == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  }

  @Test("여러 조각(8 MiB 넘음)도 한 번에 계산한 값과 같다")
  func chunks() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let data = Data((0 ..< ArchiveChecksumVerifier.chunkSize + 123).map { UInt8($0 % 251) })
    let file = directory.url.appending(path: "big")
    try data.write(to: file)

    #expect(ArchiveChecksumVerifier.hex(of: file, algorithm: .sha1)
      == Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined())
  }

  @Test("verify: 크기·체크섬이 같으면 match, 하나라도 다르면 mismatch, 파일이 없으면 mismatch")
  func verify() async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    try FileTree.file(directory.url, "f", contents: "abc")
    let file = directory.url.appending(path: "f")
    let checksum = try #require(ArchiveChecksum(algorithm: .sha1, hex: "a9993e364706816aba3e25717850c26c9cd0d89d"))
    let other = try #require(ArchiveChecksum(algorithm: .sha1, hex: String(repeating: "0", count: 40)))

    #expect(await ArchiveChecksumVerifier.verify(file, size: 3, checksum: checksum) == .match)
    #expect(await ArchiveChecksumVerifier.verify(file, size: 4, checksum: checksum) == .mismatch)
    #expect(await ArchiveChecksumVerifier.verify(file, size: 3, checksum: other) == .mismatch)
    #expect(await ArchiveChecksumVerifier
      .verify(directory.url.appending(path: "none"), size: 3, checksum: checksum) == .mismatch)
  }

  @Test("verify: 취소된 Task 면 cancelled")
  func cancelled() async throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    try FileTree.file(directory.url, "f", contents: "abc")
    let file = directory.url.appending(path: "f")
    let checksum = try #require(ArchiveChecksum(algorithm: .sha1, hex: "a9993e364706816aba3e25717850c26c9cd0d89d"))

    let outcome = await Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return await ArchiveChecksumVerifier.verify(file, size: 3, checksum: checksum)
    }.value

    #expect(outcome == .cancelled)
  }
}
