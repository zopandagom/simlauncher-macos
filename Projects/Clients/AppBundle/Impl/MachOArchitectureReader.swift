import Core
import Foundation

/// 실행 파일 앞부분(헤더)에서 시뮬레이터가 실행할 수 있는 CPU 아키텍처를 읽는다 (순수).
enum MachOArchitectureReader {
  /// thin 64비트 `MH_MAGIC_64` 의 디스크 바이트 (리틀엔디언 0xFEEDFACF).
  private static let thin64Magic: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE]
  /// thin 32비트 `MH_MAGIC` 의 디스크 바이트 (리틀엔디언 0xFEEDFACE). 시뮬레이터가 실행하지 않는다.
  private static let thin32Magic: [UInt8] = [0xCE, 0xFA, 0xED, 0xFE]
  /// `FAT_MAGIC` (빅엔디언 0xCAFEBABE), 항목 `fat_arch` 20바이트.
  private static let fatMagic: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE]
  /// `FAT_MAGIC_64` (빅엔디언 0xCAFEBABF), 항목 `fat_arch_64` 32바이트.
  private static let fat64Magic: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBF]
  /// fat 헤더(magic + `nfat_arch`) 크기.
  private static let fatHeaderSize = 8

  /// Mach-O 가 아니거나 fat 항목 수가 0 이거나 데이터 길이를 넘으면 nil (Java class 파일도 `cafebabe` 로 시작한다).
  /// thin 32비트는 빈 집합, 모르는 cputype 의 slice 는 빠진다.
  static func architectures(fromHeader data: Data) -> Set<CPUArchitecture>? {
    let bytes = [UInt8](data)
    guard bytes.count >= 4 else { return nil }
    let magic = Array(bytes[0 ..< 4])
    switch magic {
    case Self.thin64Magic:
      guard let cpuType = Self.uint32(bytes, at: 4, bigEndian: false) else { return nil }
      return Self.architecture(cpuType).map { [$0] } ?? []
    case Self.thin32Magic:
      return []
    case Self.fatMagic:
      return Self.fatArchitectures(bytes, entrySize: 20)
    case Self.fat64Magic:
      return Self.fatArchitectures(bytes, entrySize: 32)
    default:
      return nil
    }
  }

  /// 각 항목의 첫 4바이트가 빅엔디언 cputype 이다.
  private static func fatArchitectures(_ bytes: [UInt8], entrySize: Int) -> Set<CPUArchitecture>? {
    guard
      let count = uint32(bytes, at: 4, bigEndian: true).map(Int.init),
      count >= 1,
      count <= (bytes.count - fatHeaderSize) / entrySize
    else { return nil }
    var architectures: Set<CPUArchitecture> = []
    for index in 0 ..< count {
      let offset = Self.fatHeaderSize + index * entrySize
      if let cpuType = Self.uint32(bytes, at: offset, bigEndian: true), let architecture = Self.architecture(cpuType) {
        architectures.insert(architecture)
      }
    }
    return architectures
  }

  /// `CPU_TYPE_ARM64`(0x0100000C, arm64e 포함)·`CPU_TYPE_X86_64`(0x01000007). 그 밖은 nil.
  private static func architecture(_ cpuType: UInt32) -> CPUArchitecture? {
    switch cpuType {
    case 0x0100_000C: .arm64
    case 0x0100_0007: .x86_64
    default: nil
    }
  }

  private static func uint32(_ bytes: [UInt8], at offset: Int, bigEndian: Bool) -> UInt32? {
    guard offset >= 0, offset + 4 <= bytes.count else { return nil }
    let slice = bytes[offset ..< offset + 4]
    let ordered = bigEndian ? Array(slice) : Array(slice.reversed())
    return ordered.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
  }
}
