import CryptoKit
import Foundation
import Testing
@testable import Core

struct AndroidLicenseTests {
  @Test("지문 = 원문 UTF-8 의 SHA-256 소문자 hex")
  func fingerprint() {
    let license = AndroidLicense(id: "a", text: "abc")
    #expect(license.fingerprint == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    let korean = AndroidLicense(id: "a", text: "동의")
    let expected = SHA256.hash(data: Data("동의".utf8)).map { String(format: "%02x", $0) }.joined()
    #expect(korean.fingerprint == expected)
    #expect(korean.fingerprint.count == 64)
  }

  @Test("원문이 한 글자라도 다르면 지문이 다르고, id 는 지문에 들지 않는다")
  func differs() {
    #expect(AndroidLicense(id: "a", text: "Terms").fingerprint != AndroidLicense(id: "a", text: "Terms ").fingerprint)
    #expect(AndroidLicense(id: "a", text: "Terms").fingerprint == AndroidLicense(id: "b", text: "Terms").fingerprint)
  }

  @Test("licensesToConfirm 은 기록된 지문을 빼고 순서를 지킨다")
  func licensesToConfirm() {
    let first = AndroidLicense(id: "a", text: "one")
    let second = AndroidLicense(id: "b", text: "two")
    let plan = AndroidSDKInstallPlan(
      root: AndroidFixture.root,
      sdkVolumeName: nil,
      sameVolumeAsDownloads: true,
      packages: [],
      licenses: [first, second]
    )
    #expect(plan.licensesToConfirm(accepted: []) == [first, second])
    #expect(plan.licensesToConfirm(accepted: [first.fingerprint]) == [second])
    #expect(plan.licensesToConfirm(accepted: [first.fingerprint, second.fingerprint, "other"]).isEmpty)
  }

  @Test("checksum: 길이·hex 를 검사하고 소문자로 둔다")
  func checksum() {
    #expect(ArchiveChecksum(algorithm: .sha1, hex: " ABCDEF0123456789ABCDEF0123456789ABCDEF01 ")?.hex
      == "abcdef0123456789abcdef0123456789abcdef01")
    #expect(ArchiveChecksum(algorithm: .sha256, hex: String(repeating: "0", count: 64)) != nil)
    #expect(ArchiveChecksum(algorithm: .sha1, hex: String(repeating: "0", count: 64)) == nil)
    #expect(ArchiveChecksum(algorithm: .sha256, hex: String(repeating: "0", count: 40)) == nil)
    #expect(ArchiveChecksum(algorithm: .sha1, hex: String(repeating: "g", count: 40)) == nil)
  }
}
