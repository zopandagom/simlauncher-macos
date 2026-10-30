import Foundation

extension AXMLManifestReader {
  /// 범위를 확인하는 리틀 엔디언 읽기.
  struct Bytes {
    let raw: [UInt8]

    init(_ raw: [UInt8]) {
      self.raw = raw
    }

    var count: Int { self.raw.count }

    func u8(_ index: Int) -> UInt8? {
      index >= 0 && index < self.raw.count ? self.raw[index] : nil
    }

    func u16(_ index: Int) -> UInt16? {
      guard index >= 0, index + 2 <= self.raw.count else {
        return nil
      }
      return UInt16(self.raw[index]) | UInt16(self.raw[index + 1]) << 8
    }

    func u32(_ index: Int) -> UInt32? {
      guard index >= 0, index + 4 <= self.raw.count else {
        return nil
      }
      return UInt32(self.raw[index]) | UInt32(self.raw[index + 1]) << 8
        | UInt32(self.raw[index + 2]) << 16 | UInt32(self.raw[index + 3]) << 24
    }
  }

  struct Chunk {
    let start: Int
    let headerSize: Int
    let end: Int

    var body: Int { self.start + self.headerSize }
  }

  /// 첫 문자열 풀. 문자열은 필요한 색인만 꺼낼 때 디코드한다.
  struct StringPool {
    let bytes: Bytes
    let count: Int
    let offsetsStart: Int
    let stringsStart: Int
    let end: Int
    let isUTF8: Bool

    /// headerSize ≥ 28, 오프셋 표·문자열 시작이 청크 안.
    init?(bytes: Bytes, chunk: Chunk) {
      guard
        chunk.headerSize >= 28,
        let count = bytes.u32(chunk.start + 8).map(Int.init),
        let flags = bytes.u32(chunk.start + 16),
        let stringsStart = bytes.u32(chunk.start + 20).map(Int.init),
        count <= (chunk.end - chunk.body) / 4,
        chunk.start + stringsStart <= chunk.end
      else {
        return nil
      }
      self.bytes = bytes
      self.count = count
      self.offsetsStart = chunk.body
      self.stringsStart = chunk.start + stringsStart
      self.end = chunk.end
      self.isUTF8 = flags & 0x100 != 0
    }

    /// 색인이 범위 밖이거나, 끝이 청크 밖이거나, 디코드하지 못하면 nil.
    func string(_ index: UInt32) -> String? {
      guard
        Int(index) < self.count,
        let offset = self.bytes.u32(self.offsetsStart + Int(index) * 4).map(Int.init)
      else {
        return nil
      }
      let position = self.stringsStart + offset
      guard position < self.end else {
        return nil
      }
      return self.isUTF8 ? self.utf8(at: position) : self.utf16(at: position)
    }

    /// 길이 u16 (최상위 비트면 u16 두 개, 글자 수) 뒤 UTF-16LE.
    private func utf16(at position: Int) -> String? {
      guard let first = self.bytes.u16(position) else {
        return nil
      }
      var length = Int(first)
      var start = position + 2
      if first & 0x8000 != 0 {
        guard let second = self.bytes.u16(position + 2) else {
          return nil
        }
        length = Int(first & 0x7FFF) << 16 | Int(second)
        start += 2
      }
      guard start + length * 2 <= self.end else {
        return nil
      }
      let units = (0 ..< length)
        .map { UInt16(self.bytes.raw[start + $0 * 2]) | UInt16(self.bytes.raw[start + $0 * 2 + 1]) << 8 }
      // 짝 없는 서로게이트는 대체 문자로 바꾸지 않고 nil.
      return String(validating: units, as: UTF16.self)
    }

    /// 길이 두 개(UTF-16 글자 수, UTF-8 바이트 수. 각각 1~2 바이트) 뒤 UTF-8 바이트.
    private func utf8(at position: Int) -> String? {
      guard
        let (_, afterCharacters) = self.length8(at: position),
        let (byteCount, start) = self.length8(at: afterCharacters),
        start + byteCount <= self.end
      else {
        return nil
      }
      return String(validating: self.bytes.raw[start ..< start + byteCount], as: UTF8.self)
    }

    /// 1 바이트, 최상위 비트면 2 바이트 (`(b0 & 0x7F) << 8 | b1`). 값과 다음 위치.
    private func length8(at position: Int) -> (Int, Int)? {
      guard let first = self.bytes.u8(position), position < self.end else {
        return nil
      }
      guard first & 0x80 != 0 else {
        return (Int(first), position + 1)
      }
      guard let second = self.bytes.u8(position + 1), position + 1 < self.end else {
        return nil
      }
      return (Int(first & 0x7F) << 8 | Int(second), position + 2)
    }
  }

  /// 요소 속성 하나 (ResXMLTree_attribute).
  struct Attribute {
    let namespace: UInt32
    let name: UInt32
    let rawValue: UInt32
    let dataType: UInt8
    let data: UInt32
  }
}
