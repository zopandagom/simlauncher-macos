import Core
import Foundation
import Testing
@testable import AppBundleImpl

struct MachOArchitectureReaderTests {
  private static let arm64: UInt32 = 0x0100_000C
  private static let x86: UInt32 = 0x0100_0007

  @Test("thin 64비트 헤더의 cputype 을 읽는다")
  func thin() {
    #expect(Self.read(MachOBytes.thinArm64) == [.arm64])
    #expect(Self.read(MachOBytes.thinX86) == [.x86_64])
  }

  @Test("fat·fat64 헤더는 모든 항목의 아키텍처를 읽는다")
  func fat() {
    #expect(Self.read(MachOBytes.fat([Self.x86, Self.arm64])) == [.arm64, .x86_64])
    #expect(Self.read(MachOBytes.fat64([Self.x86, Self.arm64])) == [.arm64, .x86_64])
  }

  @Test("§2.2 에서 확인한 실제 fat 헤더 바이트(x86_64 + arm64)를 읽는다")
  func realFatHeader() {
    let bytes: [UInt8] = [
      0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x00, 0x00, 0x02,
      0x01, 0x00, 0x00, 0x07, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00,
      0x0E,
      0x01, 0x00, 0x00, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00,
      0x0E,
    ]
    #expect(Self.read(bytes) == [.arm64, .x86_64])
  }

  @Test("fat 의 모르는 cputype 은 빠지고, thin 32비트는 빈 집합")
  func unknownSlices() {
    #expect(Self.read(MachOBytes.fat([0x0000_000C, Self.arm64])) == [.arm64])
    #expect(Self.read(MachOBytes.fat([0x0000_0012])) == [])
    #expect(Self.read(MachOBytes.thin32) == [])
  }

  @Test("fat 항목 수가 0 이거나 데이터보다 많으면 Mach-O 로 보지 않는다")
  func invalidFatCount() {
    #expect(Self.read(MachOBytes.fat([Self.arm64], count: 2)) == nil)
    #expect(Self.read(MachOBytes.fat([], count: 0)) == nil)
    #expect(Self.read(MachOBytes.fat64([Self.arm64, Self.x86], count: 3)) == nil)
    // Java class 파일: cafebabe 뒤에 버전(0x0000_0034)이 와서 항목 수로 읽으면 데이터보다 크다.
    #expect(Self.read([0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x00, 0x00, 0x34, 0x00, 0x0A]) == nil)
  }

  @Test(
    "4바이트 미만이거나 Mach-O 가 아닌 바이트는 nil",
    arguments: [
      [UInt8](),
      [0xCF, 0xFA, 0xED],
      [0xCF, 0xFA, 0xED, 0xFE, 0x0C],
      Array("#!/bin/sh\n".utf8),
      [0x00, 0x00, 0x00, 0x00]
    ]
  )
  func notMachO(bytes: [UInt8]) {
    #expect(Self.read(bytes) == nil)
  }

  private static func read(_ bytes: [UInt8]) -> Set<CPUArchitecture>? {
    MachOArchitectureReader.architectures(fromHeader: Data(bytes))
  }
}
