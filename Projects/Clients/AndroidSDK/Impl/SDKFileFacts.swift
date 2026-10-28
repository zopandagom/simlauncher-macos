import Core
import Foundation

/// 볼륨 사실. 테스트가 주입한다.
struct SDKVolume: Equatable, Sendable {
  /// `stat` 의 `st_dev`. 두 경로가 같은 볼륨인지 비교한다. 읽지 못하면 nil (다른 볼륨으로 본다).
  let device: UInt64?
  /// `volumeNameKey`.
  let name: String?
  /// `volumeSupportsSymbolicLinksKey`. 읽지 못하면 nil (지원으로 본다).
  let supportsSymbolicLinks: Bool?
  /// `volumeSupportsExclusiveRenamingKey` (`renamex_np(RENAME_EXCL)`). 읽지 못하면 nil (지원으로 본다).
  var supportsExclusiveRenaming: Bool?

  /// 설치에 필요한 링크와 `RENAME_EXCL` 을 모두 지원하는지. 하나라도 false 면 false, 둘 다 읽지 못하면 nil.
  var supportsInstall: Bool? {
    if self.supportsSymbolicLinks == false || self.supportsExclusiveRenaming == false {
      return false
    }
    return self.supportsSymbolicLinks == nil && self.supportsExclusiveRenaming == nil ? nil : true
  }

  /// 실제 볼륨 값.
  static func read(_ url: URL) -> SDKVolume {
    var info = stat()
    let device = stat(url.path(percentEncoded: false), &info) == 0 ? UInt64(info.st_dev) : nil
    let values = try? url.resourceValues(forKeys: [
      .volumeNameKey, .volumeSupportsSymbolicLinksKey, .volumeSupportsExclusiveRenamingKey,
    ])
    return SDKVolume(
      device: device,
      name: values?.volumeName,
      supportsSymbolicLinks: values?.volumeSupportsSymbolicLinks,
      supportsExclusiveRenaming: values?.volumeSupportsExclusiveRenaming
    )
  }
}

/// 파일만 읽는 판정 도우미 (네트워크·명령 없음). 경로는 링크를 풀지 않은 값을 받고, 필요한 곳에서 따라간다.
enum SDKFiles {
  /// `source.properties` 를 읽는 상한.
  static let sourcePropertiesLimit = 64 * 1024

  /// 링크는 따라간 종류. 없음(ENOENT·ENOTDIR) → `.absent`, 깨진 링크·루프 → `.file`, 디렉터리인데 읽기·들어가기 권한이 없으면
  /// `.unreadable`, 일반 파일은 `access(X_OK)` 로 `.executableFile`·`.file`, 그 밖의 종류는 `.file`.
  static func kind(_ path: String) -> AndroidFileKind {
    let path = self.withoutTrailingSlash(path)
    var link = stat()
    guard lstat(path, &link) == 0 else {
      return errno == ENOENT || errno == ENOTDIR ? .absent : .unreadable
    }
    var info = stat()
    guard stat(path, &info) == 0 else {
      return link.st_mode & S_IFMT == S_IFLNK ? .file : .unreadable
    }
    switch info.st_mode & S_IFMT {
    case S_IFDIR:
      return access(path, R_OK | X_OK) == 0 ? .directory : .unreadable
    case S_IFREG:
      return access(path, X_OK) == 0 ? .executableFile : .file
    default:
      return .file
    }
  }

  /// SDK 위치·고른 폴더의 종류 (링크는 따라간다).
  static func rootKind(_ path: String) -> AndroidSDKRootKind {
    let path = self.withoutTrailingSlash(path)
    var link = stat()
    guard lstat(path, &link) == 0 else {
      return errno == ENOENT || errno == ENOTDIR ? .absent : .unreadable
    }
    var info = stat()
    guard stat(path, &info) == 0 else {
      guard link.st_mode & S_IFMT == S_IFLNK else {
        return .unreadable
      }
      return errno == ENOENT || errno == ELOOP || errno == ENOTDIR ? .brokenLink : .unreadable
    }
    guard info.st_mode & S_IFMT == S_IFDIR else {
      return .notDirectory
    }
    return access(path, R_OK | X_OK) == 0 ? .directory : .unreadable
  }

  /// 링크를 따라가지 않고 무엇이든 있다 (깨진 링크 포함, 끝 `/` 는 뗀다).
  static func exists(_ url: URL) -> Bool {
    var info = stat()
    return lstat(self.withoutTrailingSlash(url.path(percentEncoded: false)), &info) == 0
  }

  /// 끝 `/` 를 뗀 경로 (루트 `/` 는 그대로). 끝 `/` 가 있으면 `lstat` 이 마지막 링크를 따라가므로 링크 판정 전에 뗀다.
  static func withoutTrailingSlash(_ path: String) -> String {
    var path = path
    while path.count > 1, path.hasSuffix("/") {
      path.removeLast()
    }
    return path
  }

  /// 링크를 따라간 일반 파일이다.
  static func isRegularFile(_ path: String) -> Bool {
    var info = stat()
    return stat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG
  }

  /// 링크를 따라간 디렉터리이고 `access(W_OK)` 다.
  static func isWritableDirectory(_ url: URL) -> Bool {
    let path = url.path(percentEncoded: false)
    var info = stat()
    return stat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR && access(path, W_OK) == 0
  }

  /// `url` 의 부모부터 위로 올라가며 처음 있는 것 (링크는 따라간다). 디렉터리가 아닌 것이 먼저 있으면 그것을 돌려준다
  /// (부르는 쪽이 `isWritableDirectory` 로 거절한다). 끝까지 없으면 `/`.
  static func nearestExistingAncestor(of url: URL) -> URL {
    var current = url.standardizedFileURL
    while true {
      let parent = current.deletingLastPathComponent().standardizedFileURL
      guard parent.path(percentEncoded: false) != current.path(percentEncoded: false) else {
        return parent
      }
      var info = stat()
      if stat(parent.path(percentEncoded: false), &info) == 0 {
        return parent
      }
      current = parent
    }
  }

  /// `url` 이 있으면 그것, 없으면 가장 가까운 있는 조상 (볼륨 값을 읽을 곳).
  static func existingFolder(for url: URL) -> URL {
    var info = stat()
    return stat(url.path(percentEncoded: false), &info) == 0 ? url : self.nearestExistingAncestor(of: url)
  }

  /// `volumeAvailableCapacityForImportantUsage`, nil 이면 `volumeAvailableCapacity`, 둘 다 없으면 nil.
  static func availableCapacity(_ url: URL) -> Int64? {
    let values = try? url.resourceValues(forKeys: [
      .volumeAvailableCapacityForImportantUsageKey,
      .volumeAvailableCapacityKey,
    ])
    if let important = values?.volumeAvailableCapacityForImportantUsage {
      return important
    }
    return values?.volumeAvailableCapacity.map(Int64.init)
  }

  /// 링크를 따라간 일반 파일 `source.properties` 의 `Pkg.Revision`. 없거나 읽지 못하거나 상한을 넘으면 nil.
  static func revision(sourceProperties path: String) -> AndroidRevision? {
    guard
      self.isRegularFile(path),
      let handle = FileHandle(forReadingAtPath: path)
    else {
      return nil
    }
    defer { try? handle.close() }
    guard
      let data = try? handle.read(upToCount: self.sourcePropertiesLimit + 1),
      data.count <= self.sourcePropertiesLimit,
      let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    else {
      return nil
    }
    return self.revision(properties: text)
  }

  /// `Pkg.Revision=<값>` 줄 (키 앞뒤 공백 무시, 처음 나온 것). 값은 `AndroidRevision(_:)`.
  static func revision(properties text: String) -> AndroidRevision? {
    for line in text.split(whereSeparator: \.isNewline) {
      guard let equals = line.firstIndex(of: "=") else {
        continue
      }
      let key = line[..<equals].trimmingCharacters(in: .whitespaces)
      guard key == "Pkg.Revision" else {
        continue
      }
      return AndroidRevision(String(line[line.index(after: equals)...]))
    }
    return nil
  }

  /// 숨김(`.` 으로 시작)이 아닌 항목 이름, 이름순. 읽지 못하면 nil.
  static func visibleNames(_ path: String) -> [String]? {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
      return nil
    }
    return names.filter { !$0.hasPrefix(".") }.sorted()
  }
}

/// SDK 위치의 파일 사실 모으기.
enum SDKFileFacts {
  static func collect(
    _ choice: AndroidSDKRootChoice,
    abi: String,
    volume: (URL) -> SDKVolume
  ) -> AndroidSDKFileFacts {
    guard case let .root(root) = choice else {
      return self.empty(choice, kind: .absent, writable: false, checked: nil, supportsInstall: nil)
    }
    let rootPath = root.url.path(percentEncoded: false)
    let kind = SDKFiles.rootKind(rootPath)
    switch kind {
    case .directory:
      break
    case .absent:
      let ancestor = SDKFiles.nearestExistingAncestor(of: root.url)
      return self.empty(
        choice,
        kind: .absent,
        writable: SDKFiles.isWritableDirectory(ancestor),
        checked: ancestor,
        supportsInstall: volume(ancestor).supportsInstall
      )
    case .notDirectory, .brokenLink, .unreadable:
      return self.empty(choice, kind: kind, writable: false, checked: nil, supportsInstall: nil)
    }
    let systemImages = root.folder(for: .systemImage)
    let systemImagesKind = SDKFiles.kind(systemImages.path(percentEncoded: false))
    return AndroidSDKFileFacts(
      root: choice,
      rootKind: .directory,
      rootWritable: access(rootPath, W_OK) == 0,
      writeCheckedFolder: nil,
      systemImagesWritable: systemImagesKind != .directory || SDKFiles.isWritableDirectory(systemImages),
      volumeSupportsInstall: volume(root.url).supportsInstall,
      platformTools: self.tool(root.folder(for: .platformTools), executable: "adb"),
      emulator: self.tool(root.folder(for: .emulator), executable: "emulator"),
      systemImagesFolder: systemImagesKind,
      systemImageFolders: systemImagesKind == .directory ? self.images(in: systemImages, abi: abi) : []
    )
  }

  /// 고른 폴더의 사실과 쓸 수 있는지 (폴더와, 있으면 `system-images` 의 `access(W_OK)`).
  static func candidate(_ url: URL, volume: (URL) -> SDKVolume) -> (facts: AndroidSDKFolderFacts, writable: Bool) {
    let path = url.path(percentEncoded: false)
    let kind = SDKFiles.rootKind(path)
    guard kind == .directory else {
      return (AndroidSDKFolderFacts(kind: kind, entries: nil, volumeSupportsInstall: nil), false)
    }
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: path)).map { names in
      names.sorted().map { name in
        let child = url.appending(path: name).path(percentEncoded: false)
        var info = stat()
        return AndroidSDKFolderEntry(
          name: name,
          isDirectory: stat(child, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
        )
      }
    }
    let systemImages = url.appending(path: AndroidSDKComponent.systemImage.folderName, directoryHint: .isDirectory)
    let systemImagesWritable = SDKFiles.kind(systemImages.path(percentEncoded: false)) != .directory
      || SDKFiles.isWritableDirectory(systemImages)
    let facts = AndroidSDKFolderFacts(
      kind: .directory,
      entries: entries,
      volumeSupportsInstall: volume(url).supportsInstall
    )
    return (facts, access(path, W_OK) == 0 && systemImagesWritable)
  }

  /// 위치가 디렉터리가 아닐 때: 구성 요소 사실은 모두 없음 (judge 가 보지 않거나 셋 다 없음으로 본다).
  private static func empty(
    _ choice: AndroidSDKRootChoice,
    kind: AndroidSDKRootKind,
    writable: Bool,
    checked: URL?,
    supportsInstall: Bool?
  ) -> AndroidSDKFileFacts {
    AndroidSDKFileFacts(
      root: choice,
      rootKind: kind,
      rootWritable: writable,
      writeCheckedFolder: checked,
      systemImagesWritable: true,
      volumeSupportsInstall: supportsInstall,
      platformTools: .absent,
      emulator: .absent,
      systemImagesFolder: .absent,
      systemImageFolders: []
    )
  }

  private static func tool(_ folder: URL, executable: String) -> AndroidToolFolderFacts {
    let folderKind = SDKFiles.kind(folder.path(percentEncoded: false))
    guard folderKind == .directory else {
      return AndroidToolFolderFacts(folder: folderKind, executable: .absent, revision: nil)
    }
    return AndroidToolFolderFacts(
      folder: .directory,
      executable: SDKFiles.kind(folder.appending(path: executable).path(percentEncoded: false)),
      revision: SDKFiles
        .revision(sourceProperties: folder.appending(path: "source.properties").path(percentEncoded: false))
    )
  }

  /// `system-images/<api>/<tag>/<abi>` 로 있는 것 (링크는 따라간다), API·태그 이름순. 숨김 항목과 읽지 못한 API·태그 폴더는 건너뛴다.
  private static func images(in systemImages: URL, abi: String) -> [AndroidSystemImageFolderFacts] {
    var result: [AndroidSystemImageFolderFacts] = []
    for api in SDKFiles.visibleNames(systemImages.path(percentEncoded: false)) ?? [] {
      let apiFolder = systemImages.appending(path: api, directoryHint: .isDirectory)
      guard SDKFiles.kind(apiFolder.path(percentEncoded: false)) == .directory else {
        continue
      }
      for tag in SDKFiles.visibleNames(apiFolder.path(percentEncoded: false)) ?? [] {
        let folder = apiFolder.appending(path: tag, directoryHint: .isDirectory).appending(
          path: abi,
          directoryHint: .isDirectory
        )
        let path = folder.path(percentEncoded: false)
        let kind = SDKFiles.kind(path)
        guard kind != .absent else {
          continue
        }
        let isDirectory = kind == .directory
        result.append(AndroidSystemImageFolderFacts(
          apiFolder: api,
          tagFolder: tag,
          hasSystemImage: isDirectory && SDKFiles
            .isRegularFile(folder.appending(path: "system.img").path(percentEncoded: false)),
          unreadable: kind == .unreadable,
          revision: isDirectory
            ? SDKFiles
            .revision(sourceProperties: folder.appending(path: "source.properties").path(percentEncoded: false))
            : nil
        ))
      }
    }
    return result
  }
}
