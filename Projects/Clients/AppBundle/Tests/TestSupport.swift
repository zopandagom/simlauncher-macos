import CommandInterface
import CommandTesting
import Foundation
import Testing

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

  /// 읽기·쓰기 권한을 뺀 폴더가 있어도 지우도록 폴더마다 u+rwx 를 더하며 훑은 뒤 지운다.
  func remove() {
    FileTree.addOwnerPermissions(self.url)
    if let enumerator = FileManager.default.enumerator(at: self.url, includingPropertiesForKeys: nil) {
      for case let url as URL in enumerator {
        FileTree.addOwnerPermissions(url)
      }
    }
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

extension CommandClientFake {
  /// 명령을 부르면 안 되는 테스트용. 불리면 테스트가 실패하고 `.launchFailed` 를 던진다.
  static var unused: CommandClientFake {
    CommandClientFake { invocation throws(CommandError) in
      Issue.record("명령을 부르지 않아야 한다: \(invocation.executable.path(percentEncoded: false))")
      throw .launchFailed
    }
  }
}

/// 테스트가 만드는 파일 트리. 경로는 `base` 기준 상대 경로이고 중간 폴더를 만든다.
enum FileTree {
  static func directory(_ base: URL, _ path: String, mode: Int16? = nil) throws {
    let url = base.appending(path: path, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    if let mode {
      try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path(percentEncoded: false))
    }
  }

  static func file(_ base: URL, _ path: String, contents: String = "x") throws {
    let url = base.appending(path: path, directoryHint: .notDirectory)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: url)
  }

  /// `target` 문자열을 그대로 담은 심볼릭 링크.
  static func link(_ base: URL, _ path: String, to target: String) throws {
    let url = base.appending(path: path, directoryHint: .notDirectory)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: url.path(percentEncoded: false), withDestinationPath: target)
  }

  /// `Sample.app/Info.plist`·`Sample.app/Sample` 처럼 맨 위 .app 하나.
  static func app(_ base: URL, _ name: String = "Sample.app") throws {
    try self.file(base, "\(name)/Info.plist")
    try self.file(base, "\(name)/Sample")
  }

  /// 링크를 따라가지 않고, 폴더면 소유자 읽기·쓰기·실행 권한을 더한다.
  static func addOwnerPermissions(_ url: URL) {
    let path = url.path(percentEncoded: false)
    var info = stat()
    guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
      return
    }
    _ = chmod(path, (info.st_mode & 0o7777) | 0o700)
  }

  /// 링크를 따라가지 않은 권한 비트.
  static func mode(_ url: URL) -> mode_t? {
    var info = stat()
    guard lstat(url.path(percentEncoded: false), &info) == 0 else {
      return nil
    }
    return info.st_mode & 0o7777
  }

  /// 링크를 따라가지 않고 무엇이든 있는지.
  static func exists(_ url: URL) -> Bool {
    var info = stat()
    return lstat(url.path(percentEncoded: false), &info) == 0
  }
}

/// `env -i /usr/bin/zipinfo -s -T <zip>` 의 실제 출력 (설계 §2, macOS 26.6 에서 잡은 값).
enum ZipinfoOutput {
  static let normal = """
  Archive:  ok.zip
  Zip file size: 528 bytes, number of entries: 3
  drwxr-xr-x  2.0 unx        0 b- defN 20240101.000000 Sample.app/
  -rw-r--r--  2.0 unx      280 b- defN 20240101.000000 Sample.app/Info.plist
  -rwxr-xr-x  2.0 unx       12 b- defN 20240101.000000 Sample.app/Sample
  3 files, 292 bytes uncompressed, 180 bytes compressed:  38.4%

  """

  /// Finder 형식(`ditto -c -k --sequesterRsrc`): `__MACOSX` 와 프레임워크 상대 링크.
  static let dittoSequestered = """
  Archive:  ditto-seq.zip
  Zip file size: 5471 bytes, number of entries: 25
  drwxr-xr-x  2.1 unx        0 bx stor 20261019.203305 Sample.app/
  -rw-r--r--  2.1 unx        1 bX defN 20261019.203305 Sample.app/Sample
  drwxrwxr-x  2.1 unx        0 bx stor 20261019.203305 __MACOSX/
  drwxrwxr-x  2.1 unx        0 bx stor 20261019.203305 __MACOSX/Sample.app/
  -rw-r--r--  2.1 unx      163 bX defN 20261019.203305 __MACOSX/Sample.app/._Sample
  drwxr-xr-x  2.1 unx        0 bx stor 20261019.203305 Sample.app/Frameworks/
  drwxr-xr-x  2.1 unx        0 bx stor 20261019.203305 Sample.app/Frameworks/F.framework/
  drwxr-xr-x  2.1 unx        0 bx stor 20261019.203305 Sample.app/Frameworks/F.framework/Versions/
  drwxr-xr-x  2.1 unx        0 bx stor 20261019.203305 Sample.app/Frameworks/F.framework/Versions/A/
  -rw-r--r--  2.1 unx        1 bX defN 20261019.203305 Sample.app/Frameworks/F.framework/Versions/A/F
  drwxrwxr-x  2.1 unx        0 bx stor 20261019.203305 __MACOSX/Sample.app/Frameworks/
  drwxrwxr-x  2.1 unx        0 bx stor 20261019.203305 __MACOSX/Sample.app/Frameworks/F.framework/
  drwxrwxr-x  2.1 unx        0 bx stor 20261019.203305 __MACOSX/Sample.app/Frameworks/F.framework/Versions/
  drwxrwxr-x  2.1 unx        0 bx stor 20261019.203305 __MACOSX/Sample.app/Frameworks/F.framework/Versions/A/
  -rw-r--r--  2.1 unx      163 bX defN 20261019.203305 __MACOSX/Sample.app/Frameworks/F.framework/Versions/A/._F
  -rw-r--r--  2.1 unx      163 bX defN 20261019.203305 __MACOSX/Sample.app/Frameworks/F.framework/Versions/._A
  lrwxr-xr-x  2.1 unx        1 b- stor 20261019.203306 Sample.app/Frameworks/F.framework/Versions/Current
  -rw-r--r--  2.1 unx      163 bX defN 20261019.203305 __MACOSX/Sample.app/Frameworks/F.framework/Versions/._Current
  -rw-r--r--  2.1 unx      163 bX defN 20261019.203305 __MACOSX/Sample.app/Frameworks/F.framework/._Versions
  lrwxr-xr-x  2.1 unx       18 b- stor 20261019.203306 Sample.app/Frameworks/F.framework/F
  -rw-r--r--  2.1 unx      163 bX defN 20261019.203305 __MACOSX/Sample.app/Frameworks/F.framework/._F
  -rw-r--r--  2.1 unx      163 bX defN 20261019.203305 __MACOSX/Sample.app/Frameworks/._F.framework
  -rw-r--r--  2.1 unx      163 bX defN 20261019.203305 __MACOSX/Sample.app/._Frameworks
  -rw-r--r--  2.1 unx        1 bX defN 20261019.203305 Sample.app/Info.plist
  -rw-r--r--  2.1 unx      196 bX defN 20261019.203305 __MACOSX/Sample.app/._Info.plist
  25 files, 1522 bytes uncompressed, 831 bytes compressed:  45.4%

  """

  /// Windows 에서 만든 zip: 권한 `-rw-a--`·`-r-----`, OS `fat`.
  static let windows = """
  Archive:  windows.zip
  Zip file size: 252 bytes, number of entries: 2
  -rw-a--     2.0 fat        1 b- stor 20240101.000000 Sample.app/Info.plist
  -r-----     2.0 fat        1 b- stor 20240101.000000 Sample.app/Sample
  2 files, 2 bytes uncompressed, 2 bytes compressed:  0.0%

  """

  /// `샘플 앱.app` 과 이름에 공백·탭·개행·따옴표가 든 항목.
  static let unicode = #"""
  Archive:  unicode.zip
  Zip file size: 830 bytes, number of entries: 5
  drwxr-xr-x  2.0 unx        0 b- defN 20240101.000000 ?????? ???.app/
  -rw-r--r--  2.0 unx      280 b- defN 20240101.000000 ?????? ???.app/Info.plist
  -rwxr-xr-x  2.0 unx       12 b- defN 20240101.000000 ?????? ???.app/Sample
  -rw-r--r--  2.0 unx        1 b- defN 20240101.000000 ?????? ???.app/sp ace^Itab "q".txt
  -rw-r--r--  2.0 unx        1 b- defN 20240101.000000 ?????? ???.app/new^Jline.txt
  5 files, 294 bytes uncompressed, 186 bytes compressed:  36.7%

  """#

  /// 빈 zip (종료 코드 1).
  static let empty = """
  Archive:  empty.zip
  Zip file size: 22 bytes, number of entries: 0
  Empty zipfile.

  """

  /// 앞에 12 바이트가 붙은 zip (종료 코드 1). 헤더와 항목 사이에 경고 두 줄이 든다.
  static let prefixed = """
  Archive:  prefix.zip
  Zip file size: 540 bytes, number of entries: 3
  warning [prefix.zip]:  12 extra bytes at beginning or within zipfile
    (attempting to process anyway)
  drwxr-xr-x  2.0 unx        0 b- defN 20240101.000000 Sample.app/
  -rw-r--r--  2.0 unx      280 b- defN 20240101.000000 Sample.app/Info.plist
  -rwxr-xr-x  2.0 unx       12 b- defN 20240101.000000 Sample.app/Sample
  3 files, 292 bytes uncompressed, 180 bytes compressed:  38.4%

  """

  /// 한 항목 목록. `line` 은 항목 줄 그대로.
  static func single(_ line: String) -> String {
    """
    Archive:  one.zip
    Zip file size: 100 bytes, number of entries: 1
    \(line)
    1 file, 0 bytes uncompressed, 0 bytes compressed:  0.0%

    """
  }
}
