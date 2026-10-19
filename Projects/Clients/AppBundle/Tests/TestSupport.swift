import Foundation

/// 직접 만든 Mach-O 헤더 바이트.
enum MachOBytes {
  static let thinArm64: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]
  static let thinX86: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE, 0x07, 0x00, 0x00, 0x01, 0x03, 0x00, 0x00, 0x00]
  static let thin32: [UInt8] = [0xCE, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x00]

  /// `FAT_MAGIC` + 항목 수 + 20바이트 항목들 (cputype 빅엔디언이 첫 4바이트).
  static func fat(_ cpuTypes: [UInt32], count: UInt32? = nil) -> [UInt8] {
    self.header([0xCA, 0xFE, 0xBA, 0xBE], cpuTypes, count: count, entrySize: 20)
  }

  /// `FAT_MAGIC_64` + 항목 수 + 32바이트 항목들.
  static func fat64(_ cpuTypes: [UInt32], count: UInt32? = nil) -> [UInt8] {
    self.header([0xCA, 0xFE, 0xBA, 0xBF], cpuTypes, count: count, entrySize: 32)
  }

  private static func header(_ magic: [UInt8], _ cpuTypes: [UInt32], count: UInt32?, entrySize: Int) -> [UInt8] {
    var bytes = magic + Self.bigEndian(count ?? UInt32(cpuTypes.count))
    for cpuType in cpuTypes {
      bytes += Self.bigEndian(cpuType) + [UInt8](repeating: 0, count: entrySize - 4)
    }
    return bytes
  }

  private static func bigEndian(_ value: UInt32) -> [UInt8] {
    [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
  }
}

/// 테스트마다 만드는 임시 폴더. 끝나면 `remove()` 로 지운다.
struct TemporaryDirectory {
  /// 심볼릭 링크를 푼 경로 (`/var` → `/private/var`).
  let url: URL

  init() throws {
    let base = FileManager.default.temporaryDirectory.appending(path: "AppBundleTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    self.url = base.resolvingSymlinksInPath()
  }

  func remove() {
    try? FileManager.default.removeItem(at: self.url)
  }

  /// iOS 납작한 번들 `<name>` (Info.plist + 실행 파일). `plist` 가 nil 이면 Info.plist 를 만들지 않는다.
  @discardableResult
  func makeApp(
    _ name: String = "Sample.app",
    plist: [String: Any]? = Self.simulatorPlist,
    format: PropertyListSerialization.PropertyListFormat = .xml,
    executable: [UInt8]? = MachOBytes.thinArm64
  ) throws -> URL {
    let app = self.url.appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    if let plist {
      let data = try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0)
      try data.write(to: app.appending(path: "Info.plist"))
    }
    if let executable, let executableName = plist?["CFBundleExecutable"] as? String {
      try Data(executable).write(to: app.appending(path: executableName))
    }
    return app
  }

  func makeFile(_ name: String, contents: Data = Data("x".utf8)) throws -> URL {
    let file = self.url.appending(path: name)
    try contents.write(to: file)
    return file
  }

  /// `mkfifo` 로 이름 있는 파이프를 만든다 (열면 쓰는 쪽이 올 때까지 멈추는 파일).
  func makeFIFO(at url: URL) throws {
    try? FileManager.default.removeItem(at: url)
    guard mkfifo(url.path(percentEncoded: false), 0o600) == 0 else {
      throw CocoaError(.fileWriteUnknown)
    }
  }

  /// 시뮬레이터용 정상 Info.plist 값. `[String: Any]` 는 Sendable 이 아니라 계산 프로퍼티로 둔다.
  static var simulatorPlist: [String: Any] {
    [
      "CFBundleIdentifier": "com.example.sample",
      "CFBundleExecutable": "Sample",
      "CFBundleDisplayName": "샘플 앱",
      "CFBundleName": "Sample",
      "CFBundleShortVersionString": "1.2",
      "CFBundleVersion": "34",
      "CFBundleSupportedPlatforms": ["iPhoneSimulator"],
      "MinimumOSVersion": "17.0",
    ]
  }
}
