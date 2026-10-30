import CommandInterface
import CommandTesting
import Foundation
import Testing

/// 테스트 안에서 AXML(바이너리 AndroidManifest.xml) 바이트를 만든다. 공개 apk 를 레포에 넣지 않으려고 쓴다.
/// 형식은 aapt2 출력과 같은 청크 순서: 파일 헤더 → 문자열 풀 → 리소스 맵 → 네임스페이스 시작 → 요소들 → 네임스페이스 끝.
struct AXMLTestBuilder {
  enum Encoding {
    case utf16, utf8
  }

  /// 속성 값 (Res_value 의 dataType·data, rawValue).
  enum Value {
    /// dataType 0x10.
    case int(Int32)
    /// dataType 0x11.
    case hex(UInt32)
    /// rawValue 와 data 모두 그 문자열 색인, dataType 0x03 (aapt2 의 문자열 속성).
    case string(String)
    /// rawValue 없음(0xFFFFFFFF), data 만 문자열 색인, dataType 0x03.
    case typedString(String)
    /// dataType 0x01 (`@integer/…`).
    case reference(UInt32)
    /// dataType 0x02 (`?attr/…`).
    case attributeReference(UInt32)
  }

  struct Attribute {
    /// nil 이면 네임스페이스 없음(0xFFFFFFFF).
    var namespace: String?
    var name: String
    var value: Value

    static func android(_ name: String, _ value: Value) -> Attribute {
      Attribute(namespace: AXMLTestBuilder.androidNamespace, name: name, value: value)
    }

    static func plain(_ name: String, _ value: Value) -> Attribute {
      Attribute(namespace: nil, name: name, value: value)
    }
  }

  struct Element {
    var name: String
    var attributes: [Attribute] = []
    var children: [Element] = []
  }

  static let androidNamespace = "http://schemas.android.com/apk/res/android"
  static let minSdkVersionID: UInt32 = 0x0101_020C
  static let versionCodeID: UInt32 = 0x0101_021B

  var encoding: Encoding = .utf16
  /// 문자열 풀 맨 앞에 넣을 속성 이름과 리소스 ID. nil 이면 리소스 맵 청크를 넣지 않는다.
  var resourceMap: [(name: String, id: UInt32)]? = [
    ("versionCode", Self.versionCodeID),
    ("minSdkVersion", Self.minSdkVersionID),
  ]
  var root: Element

  /// `<manifest package=… android:versionCode="1"><uses-sdk
  /// android:minSdkVersion=…/><application><activity/></application></manifest>`.
  /// - Parameters:
  ///   - package: nil 이면 package 속성을 넣지 않는다.
  ///   - minSDK: nil 이면 `uses-sdk` 에 minSdkVersion 을 넣지 않는다.
  ///   - usesSDK: false 면 `uses-sdk` 요소를 넣지 않는다.
  static func manifest(
    package: String? = "com.example.app",
    minSDK: Value? = .int(24),
    usesSDK: Bool = true,
    encoding: Encoding = .utf16
  ) -> AXMLTestBuilder {
    var attributes: [Attribute] = [.android("versionCode", .int(1))]
    if let package {
      attributes.append(.plain("package", .string(package)))
    }
    var children: [Element] = []
    if usesSDK {
      var sdk: [Attribute] = [.android("targetSdkVersion", .int(35))]
      if let minSDK {
        sdk.insert(.android("minSdkVersion", minSDK), at: 0)
      }
      children.append(Element(name: "uses-sdk", attributes: sdk))
    }
    children.append(Element(
      name: "application",
      children: [Element(name: "activity", attributes: [.android("name", .string(".Main"))])]
    ))
    return AXMLTestBuilder(
      encoding: encoding,
      root: Element(name: "manifest", attributes: attributes, children: children)
    )
  }

  func build() -> Data {
    var strings = StringTable()
    for entry in self.resourceMap ?? [] {
      strings.index(entry.name)
    }
    strings.index("android")
    strings.index(Self.androidNamespace)
    var body: [UInt8] = []
    body += Self.chunk(
      type: 0x0100,
      headerSize: 16,
      header: Self.nodeHeader,
      body: Self.u32(strings.index("android")) + Self.u32(strings.index(Self.androidNamespace))
    )
    self.append(self.root, to: &body, strings: &strings)
    body += Self.chunk(
      type: 0x0101,
      headerSize: 16,
      header: Self.nodeHeader,
      body: Self.u32(strings.index("android")) + Self.u32(strings.index(Self.androidNamespace))
    )

    var chunks = self.stringPool(strings.values)
    if let resourceMap {
      chunks += Self.chunk(type: 0x0180, headerSize: 8, header: [], body: resourceMap.flatMap { Self.u32($0.id) })
    }
    chunks += body
    return Data(Self.chunk(type: 0x0003, headerSize: 8, header: [], body: chunks))
  }

  /// 속성 값 필드 셋 (rawValue, dataType, data).
  private struct AttributeValueFields {
    let raw: UInt32
    let type: UInt8
    let data: UInt32
  }

  private func append(_ element: Element, to bytes: inout [UInt8], strings: inout StringTable) {
    var attributes: [UInt8] = []
    for attribute in element.attributes {
      let namespace = attribute.namespace.map { strings.index($0) } ?? 0xFFFF_FFFF
      let name = strings.index(attribute.name)
      let value: AttributeValueFields = switch attribute.value {
      case let .int(value): .init(raw: 0xFFFF_FFFF, type: 0x10, data: UInt32(bitPattern: value))
      case let .hex(value): .init(raw: 0xFFFF_FFFF, type: 0x11, data: value)
      case let .string(text): .init(raw: strings.index(text), type: 0x03, data: strings.index(text))
      case let .typedString(text): .init(raw: 0xFFFF_FFFF, type: 0x03, data: strings.index(text))
      case let .reference(id): .init(raw: 0xFFFF_FFFF, type: 0x01, data: id)
      case let .attributeReference(id): .init(raw: 0xFFFF_FFFF, type: 0x02, data: id)
      }
      attributes += Self.u32(namespace) + Self.u32(name) + Self.u32(value.raw) + Self.u16(8)
        + [0, value.type] + Self.u32(value.data)
    }
    let name = strings.index(element.name)
    let ext = Self.u32(0xFFFF_FFFF) + Self.u32(name) + Self.u16(20) + Self.u16(20)
      + Self.u16(UInt16(element.attributes.count)) + Self.u16(0) + Self.u16(0) + Self.u16(0)
    bytes += Self.chunk(type: 0x0102, headerSize: 16, header: Self.nodeHeader, body: ext + attributes)
    for child in element.children {
      self.append(child, to: &bytes, strings: &strings)
    }
    bytes += Self.chunk(
      type: 0x0103,
      headerSize: 16,
      header: Self.nodeHeader,
      body: Self.u32(0xFFFF_FFFF) + Self.u32(name)
    )
  }

  private func stringPool(_ values: [String]) -> [UInt8] {
    var offsets: [UInt8] = []
    var data: [UInt8] = []
    for value in values {
      offsets += Self.u32(UInt32(data.count))
      switch self.encoding {
      case .utf16:
        let units = Array(value.utf16)
        data += Self.u16(UInt16(units.count))
        for unit in units {
          data += Self.u16(unit)
        }
        data += Self.u16(0)
      case .utf8:
        let utf8 = Array(value.utf8)
        data += [UInt8(value.utf16.count), UInt8(utf8.count)] + utf8 + [0]
      }
    }
    while data.count % 4 != 0 {
      data.append(0)
    }
    let header = Self.u32(UInt32(values.count)) + Self.u32(0) + Self.u32(self.encoding == .utf8 ? 0x100 : 0)
      + Self.u32(UInt32(28 + offsets.count)) + Self.u32(0)
    return Self.chunk(type: 0x0001, headerSize: 28, header: header, body: offsets + data)
  }

  /// 줄 번호·주석 (ResXMLTree_node 의 나머지 8 바이트).
  private static let nodeHeader = u32(1) + u32(0xFFFF_FFFF)

  /// type·headerSize·size 8 바이트 + header(나머지 헤더) + body.
  static func chunk(type: UInt16, headerSize: UInt16, header: [UInt8], body: [UInt8]) -> [UInt8] {
    self.u16(type) + self.u16(headerSize) + self.u32(UInt32(8 + header.count + body.count)) + header + body
  }

  static func u16(_ value: UInt16) -> [UInt8] {
    [UInt8(value & 0xFF), UInt8(value >> 8)]
  }

  static func u32(_ value: UInt32) -> [UInt8] {
    [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24)]
  }

  /// 처음 넣은 순서대로 색인을 준다.
  private struct StringTable {
    var values: [String] = []

    @discardableResult
    mutating func index(_ value: String) -> UInt32 {
      if let index = self.values.firstIndex(of: value) {
        return UInt32(index)
      }
      self.values.append(value)
      return UInt32(self.values.count - 1)
    }
  }
}

/// 만든 AXML 바이트를 고치는 도우미.
enum AXMLBytes {
  /// 파일 헤더 뒤 청크의 (type, 시작 위치), 순서대로.
  static func chunks(_ data: Data) -> [(type: UInt16, offset: Int)] {
    var result: [(UInt16, Int)] = []
    var offset = 8
    while offset + 8 <= data.count {
      result.append((self.u16(data, offset), offset))
      offset += Int(self.u32(data, offset + 4))
    }
    return result
  }

  /// 그 type 의 첫 청크 시작 위치.
  static func first(_ type: UInt16, in data: Data) -> Int {
    self.chunks(data).first { $0.type == type }!.offset
  }

  static func u16(_ data: Data, _ position: Int) -> UInt16 {
    UInt16(data[position]) | UInt16(data[position + 1]) << 8
  }

  static func u32(_ data: Data, _ position: Int) -> UInt32 {
    UInt32(data[position]) | UInt32(data[position + 1]) << 8 | UInt32(data[position + 2]) << 16 |
      UInt32(data[position + 3]) << 24
  }

  static func set16(_ data: inout Data, _ position: Int, _ value: UInt16) {
    data.replaceSubrange(position ..< position + 2, with: AXMLTestBuilder.u16(value))
  }

  static func set32(_ data: inout Data, _ position: Int, _ value: UInt32) {
    data.replaceSubrange(position ..< position + 4, with: AXMLTestBuilder.u32(value))
  }
}

/// 고정 시드 난수 (SplitMix64). 견고성 테스트를 매번 같은 입력으로 돌린다.
struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    self.state = seed
  }

  mutating func next() -> UInt64 {
    self.state &+= 0x9E37_79B9_7F4A_7C15
    var mixed = self.state
    mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
    return mixed ^ (mixed >> 31)
  }
}

/// zip 끝부분 바이트 (EOCD·서명 블록 매직).
enum ZipTail {
  static let signingBlockMagic = Array("APK Sig Block 42".utf8)

  /// 22 바이트 EOCD + 주석. `centralDirectoryOffset` 은 중앙 디렉터리 시작 위치.
  static func eocd(centralDirectoryOffset: UInt32, comment: [UInt8] = []) -> [UInt8] {
    [0x50, 0x4B, 0x05, 0x06] + [UInt8](repeating: 0, count: 12) + AXMLTestBuilder.u32(centralDirectoryOffset)
      + AXMLTestBuilder.u16(UInt16(comment.count)) + comment
  }

  /// `[앞 바이트][서명 블록 끝 16 바이트 또는 다른 16 바이트][중앙 디렉터리 자리 cd 바이트][EOCD]` 로 만든 파일 전체.
  static func file(signed: Bool, prefix: Int = 100, centralDirectory: Int = 46, comment: [UInt8] = []) -> [UInt8] {
    let block = signed ? self.signingBlockMagic : [UInt8](repeating: 0x41, count: 16)
    let before = [UInt8](repeating: 0, count: prefix) + block
    return before + [UInt8](repeating: 0x43, count: centralDirectory)
      + self.eocd(centralDirectoryOffset: UInt32(before.count), comment: comment)
  }
}

/// 테스트마다 만드는 임시 폴더. 끝나면 `remove()` 로 지운다.
struct TemporaryDirectory {
  /// `realpath` 로 푼 경로 (`/var` → `/private/var`). Impl 의 `location`·링크 대상과 같은 형식이다
  /// (`resolvingSymlinksInPath()` 는 `/private` 를 떼어 다르다).
  let url: URL

  init() throws {
    let base = FileManager.default.temporaryDirectory.appending(path: "AndroidPackageTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    guard let resolved = realpath(base.path(percentEncoded: false), nil) else {
      throw CocoaError(.fileNoSuchFile)
    }
    defer { free(resolved) }
    self.url = URL(filePath: String(cString: resolved), directoryHint: .isDirectory)
  }

  func remove() {
    try? FileManager.default.removeItem(at: self.url)
  }

  func makeFile(_ name: String, contents: Data = Data("x".utf8)) throws -> URL {
    let file = self.url.appending(path: name, directoryHint: .notDirectory)
    try contents.write(to: file)
    return file
  }

  func makeDirectory(_ name: String) throws -> URL {
    let folder = self.url.appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }
}

extension CommandClientFake {
  /// 명령을 부르면 안 되는 테스트용. 불리면 테스트가 실패하고 `.launchFailed` 를 던진다.
  static var unused: CommandClientFake {
    CommandClientFake { invocation throws(CommandError) in
      Issue.record("명령을 부르지 않아야 한다: \(invocation.executable.path(percentEncoded: false))")
      throw .launchFailed
    }
  }
}

/// `zipinfo -s -T` 출력 모양 (설계 실측: 실제 apk 는 `-rw----` fat·`-rw-r--r--` unx, Python 이 만든 zip 은 `?rw-------`).
enum ZipinfoOutput {
  /// 항목 줄 하나. 권한 열 뒤 버전·OS·크기·플래그·방식·시각·이름.
  static func line(
    _ name: String,
    size: Int64 = 100,
    permissions: String = "-rw-r--r--",
    os hostSystem: String = "unx"
  ) -> String {
    "\(permissions)  2.0 \(hostSystem) \(String(size).leftPadded(8)) b- defN 20081231.190000 \(name)"
  }

  /// 헤더 두 줄 + 항목 줄 + 요약 줄.
  static func listing(_ lines: [String]) -> String {
    """
    Archive:  source.apk
    Zip file size: 12345 bytes, number of entries: \(lines.count)
    \(lines.joined(separator: "\n"))
    \(lines.count) files, 0 bytes uncompressed, 0 bytes compressed:  0.0%

    """
  }

  /// manifest·classes.dex·v1 서명 파일이 든 정상 apk.
  static let signed = listing([
    line("AndroidManifest.xml", size: 2048),
    line("classes.dex"),
    line("resources.arsc"),
    line("META-INF/CERT.SF"),
    line("META-INF/CERT.RSA"),
  ])

  /// v1 서명 파일 없음 (v2+ 블록 유무는 파일 끝이 정한다).
  static let withoutV1 = listing([
    line("AndroidManifest.xml", size: 2048),
    line("classes.dex"),
  ])
}

private extension String {
  func leftPadded(_ width: Int) -> String {
    String(repeating: " ", count: max(0, width - self.count)) + self
  }
}
