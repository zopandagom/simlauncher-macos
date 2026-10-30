import Core
import Foundation

/// AndroidManifest.xml(AXML, 바이너리 XML) 에서 읽은 값.
struct AXMLManifest: Equatable {
  /// manifest 의 `package` 속성 그대로 (형식 검사는 Impl 이 `AndroidPackageName` 으로 한다).
  let package: String
  let minSDK: AndroidMinSDK
}

/// AXML 최소 해석: manifest 의 package 와 manifest 바로 아래 첫 `uses-sdk` 의 minSdkVersion 만 읽는다.
/// launcher 화면·versionCode 는 읽지 않는다 (실행할 화면은 기기에 묻는다).
/// 임의 바이트에도 범위 넘침·무한 루프 없이 nil 을 돌려준다: 모든 읽기가 범위를 확인하고, 청크마다 8 바이트 이상 전진한다.
enum AXMLManifestReader {
  /// 입력 상한 (실측 최대 121,980 바이트).
  static let sizeLimit = 4 * 1_048_576
  /// 요소 깊이 상한. 넘으면 nil.
  static let maxDepth = 64

  static let minSdkVersionResourceID: UInt32 = 0x0101_020C
  static let androidNamespace = "http://schemas.android.com/apk/res/android"

  private enum ChunkType {
    static let xml: UInt16 = 0x0003
    static let stringPool: UInt16 = 0x0001
    static let resourceMap: UInt16 = 0x0180
    static let startElement: UInt16 = 0x0102
    static let endElement: UInt16 = 0x0103
  }

  private enum ValueType {
    static let string: UInt8 = 0x03
    static let intDec: UInt8 = 0x10
    static let intHex: UInt8 = 0x11
  }

  /// 색인 없음 (`0xFFFFFFFF`).
  private static let noIndex: UInt32 = 0xFFFF_FFFF

  /// 파일 헤더(type 0x0003) → 청크 순회 → 첫 문자열 풀·첫 리소스 맵 → 요소 시작·끝으로 깊이 추적.
  /// 첫 요소가 `manifest` 가 아니거나 package 가 없으면 nil. `uses-sdk` 나 minSdkVersion 이 없으면 `.level(1)`.
  static func read(_ data: Data) -> AXMLManifest? {
    guard data.count <= self.sizeLimit else {
      return nil
    }
    let bytes = Bytes([UInt8](data))
    guard
      bytes.u16(0) == ChunkType.xml,
      let headerSize = bytes.u16(2).map(Int.init),
      let fileSize = bytes.u32(4).map(Int.init),
      headerSize >= 8,
      fileSize >= headerSize,
      fileSize <= bytes.count
    else {
      return nil
    }
    var parser = Parser(bytes: bytes)
    var offset = headerSize
    while fileSize - offset >= 8 {
      guard
        let type = bytes.u16(offset),
        let chunkHeaderSize = bytes.u16(offset + 2).map(Int.init),
        let chunkSize = bytes.u32(offset + 4).map(Int.init),
        chunkHeaderSize >= 8,
        chunkSize >= chunkHeaderSize,
        offset + chunkSize <= fileSize
      else {
        return nil
      }
      let chunk = Chunk(start: offset, headerSize: chunkHeaderSize, end: offset + chunkSize)
      guard parser.consume(type: type, chunk: chunk) else {
        return nil
      }
      offset += chunkSize
    }
    guard let package = parser.package else {
      return nil
    }
    return AXMLManifest(package: package, minSDK: parser.minSDK ?? .level(1))
  }

  /// 청크를 받으며 값을 모은다.
  private struct Parser {
    let bytes: Bytes
    var pool: StringPool?
    var resourceMap: [UInt32]?
    var depth = 0
    var sawFirstElement = false
    var package: String?
    var sawUsesSDK = false
    var minSDK: AndroidMinSDK?

    init(bytes: Bytes) {
      self.bytes = bytes
    }

    /// 형식이 어긋나면 false. 모르는 청크는 건너뛴다.
    mutating func consume(type: UInt16, chunk: Chunk) -> Bool {
      switch type {
      case ChunkType.stringPool:
        guard self.pool == nil else {
          return true
        }
        guard let pool = StringPool(bytes: self.bytes, chunk: chunk) else {
          return false
        }
        self.pool = pool
        return true
      case ChunkType.resourceMap:
        if self.resourceMap == nil {
          let count = (chunk.end - chunk.body) / 4
          self.resourceMap = (0 ..< count).compactMap { self.bytes.u32(chunk.body + $0 * 4) }
        }
        return true
      case ChunkType.startElement:
        return self.startElement(chunk)
      case ChunkType.endElement:
        self.depth = max(0, self.depth - 1)
        return true
      default:
        return true
      }
    }

    /// headerSize ≥ 16, 확장(20 바이트)과 모든 속성이 청크 안, attributeSize ≥ 20, 깊이 ≤ 64, 첫 요소는 manifest.
    private mutating func startElement(_ chunk: Chunk) -> Bool {
      let ext = chunk.body
      guard
        chunk.headerSize >= 16,
        ext + 20 <= chunk.end,
        let name = self.bytes.u32(ext + 4),
        let attributeStart = self.bytes.u16(ext + 8).map(Int.init),
        let attributeSize = self.bytes.u16(ext + 10).map(Int.init),
        let attributeCount = self.bytes.u16(ext + 12).map(Int.init),
        attributeSize >= 20,
        ext + attributeStart + attributeCount * attributeSize <= chunk.end,
        let pool = self.pool
      else {
        return false
      }
      self.depth += 1
      guard self.depth <= AXMLManifestReader.maxDepth else {
        return false
      }
      let elementName = pool.string(name)
      let attributes = (0 ..< attributeCount).compactMap { index in
        self.attribute(at: ext + attributeStart + index * attributeSize)
      }
      if !self.sawFirstElement {
        self.sawFirstElement = true
        guard elementName == "manifest" else {
          return false
        }
        self.package = self.packageValue(attributes, pool: pool)
      } else if self.depth == 2, !self.sawUsesSDK, elementName == "uses-sdk" {
        self.sawUsesSDK = true
        self.minSDK = self.minSDKValue(attributes, pool: pool)
      }
      return true
    }

    private func attribute(at position: Int) -> Attribute? {
      guard
        let namespace = self.bytes.u32(position),
        let name = self.bytes.u32(position + 4),
        let rawValue = self.bytes.u32(position + 8),
        let dataType = self.bytes.u8(position + 15),
        let data = self.bytes.u32(position + 16)
      else {
        return nil
      }
      return Attribute(namespace: namespace, name: name, rawValue: rawValue, dataType: dataType, data: data)
    }

    /// ns 없음·이름 `package` 의 rawValue 문자열, 없으면 문자열 값(dataType 0x03) 의 data 색인.
    private func packageValue(_ attributes: [Attribute], pool: StringPool) -> String? {
      guard let attribute = attributes.first(where: {
        $0.namespace == AXMLManifestReader.noIndex && pool.string($0.name) == "package"
      }) else {
        return nil
      }
      return self.stringValue(attribute, pool: pool)
    }

    /// 리소스 맵의 ID 로 찾고, 맵으로 찾지 못하면 android 네임스페이스·이름 `minSdkVersion` 으로 찾는다. 없으면 `.level(1)`.
    private func minSDKValue(_ attributes: [Attribute], pool: StringPool) -> AndroidMinSDK {
      let map = self.resourceMap ?? []
      let byID = attributes
        .first { Int($0.name) < map.count && map[Int($0.name)] == AXMLManifestReader.minSdkVersionResourceID }
      let byName = attributes.first {
        pool.string($0.namespace) == AXMLManifestReader.androidNamespace && pool.string($0.name) == "minSdkVersion"
      }
      guard let attribute = byID ?? byName else {
        return .level(1)
      }
      switch attribute.dataType {
      case ValueType.intDec, ValueType.intHex:
        return Self.level(Int(Int32(bitPattern: attribute.data)))
      case ValueType.string:
        guard let text = self.stringValue(attribute, pool: pool), let value = Int(text) else {
          return .unresolved
        }
        return Self.level(value)
      default:
        return .unresolved
      }
    }

    private func stringValue(_ attribute: Attribute, pool: StringPool) -> String? {
      if attribute.rawValue != AXMLManifestReader.noIndex, let raw = pool.string(attribute.rawValue) {
        return raw
      }
      guard attribute.dataType == ValueType.string else {
        return nil
      }
      return pool.string(attribute.data)
    }

    /// 1...10,000 밖이면 `.unresolved`.
    private static func level(_ value: Int) -> AndroidMinSDK {
      (1 ... 10000).contains(value) ? .level(value) : .unresolved
    }
  }
}
