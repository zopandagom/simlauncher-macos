import Foundation
import Testing
@testable import AndroidPackageImpl

struct APKSignatureCheckTests {
  @Test("중앙 디렉터리 바로 앞 16 바이트가 매직이면 true")
  func signed() {
    #expect(Self.check(ZipTail.file(signed: true)) == true)
  }

  @Test("매직이 아니면 false")
  func unsigned() {
    #expect(Self.check(ZipTail.file(signed: false)) == false)
  }

  @Test("EOCD 가 없으면 nil")
  func noEOCD() {
    #expect(Self.check([UInt8](repeating: 0x41, count: 200)) == nil)
    #expect(Self.check([0x50, 0x4B]) == nil)
  }

  @Test("Zip64(오프셋 0xFFFFFFFF) 면 nil")
  func zip64() {
    let bytes = [UInt8](repeating: 0, count: 100) + ZipTail.eocd(centralDirectoryOffset: 0xFFFF_FFFF)
    #expect(Self.check(bytes) == nil)
  }

  @Test("오프셋 < 16 이면 nil", arguments: [UInt32(0), 15])
  func smallOffset(offset: UInt32) {
    let bytes = [UInt8](repeating: 0, count: 100) + ZipTail.eocd(centralDirectoryOffset: offset)
    #expect(Self.check(bytes) == nil)
  }

  @Test("오프셋이 EOCD 보다 뒤면 nil")
  func offsetBeyondEOCD() {
    let bytes = [UInt8](repeating: 0, count: 100) + ZipTail.eocd(centralDirectoryOffset: 101)
    #expect(Self.check(bytes) == nil)
  }

  @Test("주석 안의 가짜 EOCD 는 무시하고 주석 길이가 끝과 맞는 진짜 EOCD 를 쓴다")
  func fakeEOCDInComment() {
    // 주석 안의 가짜 EOCD 는 오프셋 0xFFFFFFFF 라 받으면 nil 이 된다. 진짜는 서명 블록을 가리킨다.
    let fake = ZipTail.eocd(centralDirectoryOffset: 0xFFFF_FFFF)
    #expect(Self.check(ZipTail.file(signed: true, comment: fake + [1, 2, 3])) == true)
    #expect(Self.check(ZipTail.file(signed: false, comment: fake + [9])) == false)
  }

  @Test("주석 최대 길이(65,535)에서도 tail 안에서 EOCD 를 찾는다")
  func maxComment() {
    let file = ZipTail.file(signed: true, comment: [UInt8](repeating: 0x20, count: 0xFFFF))
    let tail = Array(file.suffix(APKSignatureCheck.tailLength))
    #expect(tail.count == APKSignatureCheck.tailLength)
    #expect(Self.check(file, tail: tail) == true)
  }

  @Test("블록 위치가 tail 밖이어도 read 로 읽는다")
  func blockOutsideTail() {
    let file = ZipTail.file(signed: true, centralDirectory: 70000)
    let tail = Array(file.suffix(APKSignatureCheck.tailLength))
    #expect(Self.check(file, tail: tail) == true)
  }

  @Test("read 가 실패하면 nil")
  func readFails() {
    let file = ZipTail.file(signed: true)
    let result = APKSignatureCheck.hasSigningBlock(tail: Data(file), fileSize: UInt64(file.count)) { _, _ in nil }
    #expect(result == nil)
  }

  @Test("파일 경로로 읽기: 서명 블록 있음·없음·없는 파일")
  func atPath() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    let signed = try directory.makeFile("s.apk", contents: Data(ZipTail.file(signed: true)))
    let unsigned = try directory.makeFile("u.apk", contents: Data(ZipTail.file(signed: false)))

    #expect(APKSignatureCheck.hasSigningBlock(atPath: signed.path(percentEncoded: false)) == true)
    #expect(APKSignatureCheck.hasSigningBlock(atPath: unsigned.path(percentEncoded: false)) == false)
    #expect(APKSignatureCheck
      .hasSigningBlock(atPath: directory.url.appending(path: "none.apk").path(percentEncoded: false)) == nil)
  }

  /// 파일 전체를 메모리에 두고 `read` 로 그 범위를 돌려준다. tail 을 주지 않으면 끝 `tailLength` 바이트.
  private static func check(_ file: [UInt8], tail: [UInt8]? = nil) -> Bool? {
    let tail = tail ?? Array(file.suffix(APKSignatureCheck.tailLength))
    return APKSignatureCheck.hasSigningBlock(tail: Data(tail), fileSize: UInt64(file.count)) { offset, count in
      let start = Int(offset)
      guard start + count <= file.count else {
        return nil
      }
      return Data(file[start ..< start + count])
    }
  }
}
