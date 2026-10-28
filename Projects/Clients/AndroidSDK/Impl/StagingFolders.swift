import Foundation
import Synchronization

/// SDK 폴더 안 `.simlauncher-staging-<UUID>` 스테이징 폴더의 이름 등록과 삭제 (AppBundle `ExtractionFolders` 와 같은 지우기 규칙).
/// 폴더를 만들기 전에 이름을 등록하므로, Android 화면을 열 때 하는 정리가 지금 쓰는 폴더를 지우지 않는다.
/// 그 밖의 SDK 안 항목은 절대 지우지 않는다.
final class StagingFolders: Sendable {
  static let prefix = ".simlauncher-staging-"

  private let live = Mutex<Set<String>>([])

  /// 새 폴더 이름 (`.simlauncher-staging-<UUID>`).
  static func newName() -> String {
    self.prefix + UUID().uuidString
  }

  func register(_ name: String) {
    _ = self.live.withLock { $0.insert(name) }
  }

  func isLive(_ name: String) -> Bool {
    self.live.withLock { $0.contains(name) }
  }

  /// 형식에 맞으면 지우고, 형식과 상관없이 이름 등록을 푼다. 실패는 무시한다 (다음 정리가 다시 지운다).
  func remove(_ folder: URL, root: String) {
    if Self.isStagingFolder(folder, root: root) {
      Self.forceRemove(folder)
    }
    _ = self.live.withLock { $0.remove(folder.lastPathComponent) }
  }

  /// `root`(실제 경로) 바로 아래에서 형식에 맞고 등록되지 않은 스테이징을 지운다. 실패는 무시한다.
  func removeLeftovers(root: String) {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else {
      return
    }
    for name in names where Self.isStagingName(name) && !self.isLive(name) {
      let folder = URL(filePath: root, directoryHint: .isDirectory).appending(path: name, directoryHint: .isDirectory)
      if Self.isStagingFolder(folder, root: root) {
        Self.forceRemove(folder)
      }
    }
  }

  /// 이름이 정확히 `.simlauncher-staging-` + UUID 로 읽히는 UUID 이고, 부모의 실제 경로가 SDK 루트의 실제 경로와 같고,
  /// `lstat`(끝 `/` 를 뗀 경로) 으로 링크가 아닌 디렉터리다.
  static func isStagingFolder(_ folder: URL, root: String) -> Bool {
    guard
      self.isStagingName(folder.lastPathComponent),
      let parent = RealPath.of(folder.deletingLastPathComponent()),
      let rootReal = RealPath.of(root),
      parent == rootReal
    else {
      return false
    }
    var info = stat()
    let path = SDKFiles.withoutTrailingSlash(folder.path(percentEncoded: false))
    return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
  }

  static func isStagingName(_ name: String) -> Bool {
    name.hasPrefix(self.prefix) && UUID(uuidString: String(name.dropFirst(self.prefix.count))) != nil
  }

  /// zip 이 읽기·쓰기 권한 없는 폴더를 만들 수 있어 `removeItem` 만으로는 일부만 지워진다 (숨김 폴더에 최대 5.7 GB 가 남는다).
  /// 루트에 먼저 u+rwx 를 더하고, 폴더를 받을 때마다(그 폴더의 자식을 읽기 전에) u+rwx 를 더하며 훑은 뒤 지운다.
  /// 링크는 따라가지도 바꾸지도 않는다.
  static func forceRemove(_ folder: URL) {
    self.addOwnerPermissions(folder)
    if let enumerator = FileManager.default.enumerator(
      at: folder,
      includingPropertiesForKeys: [.fileResourceTypeKey],
      options: [],
      errorHandler: { _, _ in true }
    ) {
      for case let url as URL in enumerator
        where (try? url.resourceValues(forKeys: [.fileResourceTypeKey]).fileResourceType) == .directory
      {
        self.addOwnerPermissions(url)
      }
    }
    try? FileManager.default.removeItem(at: folder)
  }

  /// 링크를 따라가지 않고, 폴더면 소유자 읽기·쓰기·실행 권한을 더한다.
  private static func addOwnerPermissions(_ url: URL) {
    let path = SDKFiles.withoutTrailingSlash(url.path(percentEncoded: false))
    var info = stat()
    guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
      return
    }
    _ = chmod(path, (info.st_mode & 0o7777) | 0o700)
  }
}
