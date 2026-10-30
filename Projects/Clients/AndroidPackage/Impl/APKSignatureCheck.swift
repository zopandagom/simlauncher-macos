import Foundation

/// v2+ 서명 블록(APK Signing Block) 유무. 블록은 중앙 디렉터리 바로 앞에 있고 마지막 16 바이트가 `APK Sig Block 42` 다.
/// 블록 안의 서명은 검증하지 않는다 (최종 판정은 기기 PackageManager).
enum APKSignatureCheck {
  /// 파일 끝에서 읽는 최대 길이: EOCD 22 바이트 + 주석 최대 65,535 바이트.
  static let tailLength = 22 + 0xFFFF

  /// 블록 마지막 16 바이트.
  static let magic = Data("APK Sig Block 42".utf8)

  /// `fileSize` 의 파일 끝 `tail`(최대 `tailLength`) 에서 EOCD 를 찾아 중앙 디렉터리 오프셋 바로 앞 16 바이트를 `read` 로 읽는다.
  /// EOCD 는 끝에서 앞으로 `PK\x05\x06` 을 찾되 `EOCD + 22 + 주석 길이 == tail 끝` 인 것만 받는다 (주석 안의 가짜 서명 무시).
  /// - Returns: 매직이 맞으면 true, 아니면 false. 모르면 nil: EOCD 없음, Zip64(오프셋 0xFFFFFFFF), 오프셋 < 16,
  ///   오프셋이 EOCD 보다 뒤(범위 밖), `read` 실패.
  static func hasSigningBlock(
    tail: Data,
    fileSize: UInt64,
    read: (_ offset: UInt64, _ count: Int) -> Data?
  ) -> Bool? {
    let bytes = [UInt8](tail)
    guard bytes.count >= 22, UInt64(bytes.count) <= fileSize else {
      return nil
    }
    for start in stride(from: bytes.count - 22, through: 0, by: -1) {
      guard bytes[start] == 0x50, bytes[start + 1] == 0x4B, bytes[start + 2] == 0x05, bytes[start + 3] == 0x06 else {
        continue
      }
      let commentLength = Int(bytes[start + 20]) | Int(bytes[start + 21]) << 8
      guard start + 22 + commentLength == bytes.count else {
        continue
      }
      let offset = UInt64(bytes[start + 16]) | UInt64(bytes[start + 17]) << 8
        | UInt64(bytes[start + 18]) << 16 | UInt64(bytes[start + 19]) << 24
      let eocdOffset = fileSize - UInt64(bytes.count) + UInt64(start)
      guard offset != 0xFFFF_FFFF, offset >= 16, offset <= eocdOffset else {
        return nil
      }
      guard let found = read(offset - 16, 16) else {
        return nil
      }
      return found == self.magic
    }
    return nil
  }

  /// 파일을 열어 끝부분을 읽고 `hasSigningBlock(tail:fileSize:read:)` 를 부른다. 열거나 읽지 못하면 nil.
  static func hasSigningBlock(atPath path: String) -> Bool? {
    guard let handle = FileHandle(forReadingAtPath: path) else {
      return nil
    }
    defer { try? handle.close() }
    do {
      let fileSize = try handle.seekToEnd()
      let tailStart = fileSize - min(fileSize, UInt64(self.tailLength))
      try handle.seek(toOffset: tailStart)
      let tail = try handle.read(upToCount: self.tailLength) ?? Data()
      return self.hasSigningBlock(tail: tail, fileSize: fileSize) { offset, count in
        do {
          try handle.seek(toOffset: offset)
          return try handle.read(upToCount: count)
        } catch {
          return nil
        }
      }
    } catch {
      return nil
    }
  }
}
