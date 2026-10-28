import AndroidEmulatorInterface
import Core
import Foundation

/// `~/.android/avd` 의 `<이름>.ini` 하나.
struct AVDEntry: Sendable {
  /// 파일 이름에서 `.ini` 를 뗀 것 (Core 이름 검사 전 값. 공백·한글일 수 있다).
  let name: String
  /// 폴더 목록에서 찾은 ini 항목 URL. 삭제는 이름으로 경로를 만들지 않고 이것을 쓴다.
  let pointerURL: URL
  /// ini 의 `path`·`path.rel` 로 정한 기기 폴더. 둘 다 쓸 수 없으면 nil.
  let folder: URL?
}

/// AVD 폴더 읽기 (파일만, 명령 없음).
enum AVDFolderScan {
  static let pointerExtension = ".ini"
  static let folderExtension = ".avd"
  static let configFileName = "config.ini"

  /// `home/.android`.
  static func androidFolder(home: URL) -> URL {
    home.appending(path: ".android", directoryHint: .isDirectory)
  }

  /// `home/.android/avd`.
  static func avdFolder(home: URL) -> URL {
    self.androidFolder(home: home).appending(path: "avd", directoryHint: .isDirectory)
  }

  /// `avd` 폴더 안 이름. 폴더가 없으면 nil (만들지 않는다), 있는데 읽지 못하면 `.avdFolderUnavailable`.
  static func childNames(home: URL) throws(AndroidEmulatorError) -> [String]? {
    let folder = self.avdFolder(home: home)
    if FileFacts.kindWithoutFollowing(folder) == .absent {
      return nil
    }
    do {
      return try FileManager.default.contentsOfDirectory(atPath: FileFacts.path(folder)).sorted()
    } catch {
      throw .avdFolderUnavailable
    }
  }

  /// `<이름>.ini` 일반 파일(링크·디렉터리는 건너뛴다)마다 하나. 빈 이름·`.`·`..` 은 뺀다.
  static func entries(home: URL) throws(AndroidEmulatorError) -> [AVDEntry] {
    guard let names = try self.childNames(home: home) else {
      return []
    }
    let folder = self.avdFolder(home: home)
    return names.compactMap { fileName in
      guard fileName.hasSuffix(self.pointerExtension) else {
        return nil
      }
      let name = String(fileName.dropLast(self.pointerExtension.count))
      guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
        return nil
      }
      let pointerURL = folder.appending(path: fileName, directoryHint: .notDirectory)
      guard FileFacts.kindWithoutFollowing(pointerURL) == .file else {
        return nil
      }
      let pairs = FileFacts.read(pointerURL, limit: AVDIniFile.maxByteCount).flatMap(AVDIniFile.parse)
      return AVDEntry(name: name, pointerURL: pointerURL, folder: pairs.flatMap { self.deviceFolder($0, home: home) })
    }
  }

  /// 만들기의 이름 충돌 검사용: `avd` 안의 `*.ini`·`*.avd` 이름 (확장자를 뗀 것, 종류는 보지 않는다). 폴더가 없으면 빈 집합.
  static func takenNames(home: URL) throws(AndroidEmulatorError) -> Set<String> {
    let names = try self.childNames(home: home) ?? []
    var taken: Set<String> = []
    for name in names {
      for suffix in [self.pointerExtension, self.folderExtension] where name.hasSuffix(suffix) {
        taken.insert(String(name.dropLast(suffix.count)))
      }
    }
    return taken
  }

  /// 기기 폴더: `path` 가 `/` 로 시작하면 그 경로. 아니면(없거나 상대) `path.rel` 이 `..`·빈 구성 요소 없는 상대 경로일 때
  /// `home/.android/<path.rel>`. 둘 다 아니면 nil.
  static func deviceFolder(_ pairs: [(key: String, value: String)], home: URL) -> URL? {
    if let path = AVDIniFile.value(for: "path", in: pairs), path.hasPrefix("/") {
      return URL(filePath: path, directoryHint: .isDirectory)
    }
    guard let relative = AVDIniFile.value(for: "path.rel", in: pairs), !relative.hasPrefix("/") else {
      return nil
    }
    var components = relative.split(separator: "/", omittingEmptySubsequences: false)
    if components.count > 1, components.last?.isEmpty == true {
      components.removeLast()
    }
    guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != ".." && !$0.contains("\0") }) else {
      return nil
    }
    var url = self.androidFolder(home: home)
    for component in components {
      url = url.appending(path: String(component), directoryHint: .isDirectory)
    }
    return url
  }

  /// 판정에 쓸 사실. 이미지 설치 여부는 지금 SDK(`tools`)에서 본다.
  static func facts(_ entry: AVDEntry, tools: SDKTools) -> AndroidAVDFacts {
    guard let folder = entry.folder, FileFacts.isDirectory(folder) else {
      return AndroidAVDFacts(name: entry.name, folderExists: false, config: nil, imageInstalled: false, lockHeld: nil)
    }
    let configURL = folder.appending(path: self.configFileName, directoryHint: .notDirectory)
    let config = FileFacts.read(configURL, limit: AVDIniFile.maxByteCount).flatMap(AVDIniFile.parse)
    let image = config
      .flatMap { AVDIniFile.value(for: "image.sysdir.1", in: $0) }
      .flatMap(AndroidSystemImageRef.parse(sysdir:))
    return AndroidAVDFacts(
      name: entry.name,
      folderExists: true,
      config: config,
      imageInstalled: image.map(tools.isInstalled) ?? false,
      lockHeld: AVDLock.isHeld(folder: folder)
    )
  }
}
