import Foundation
import Synchronization

/// `extractApp(fromZip:)` 이 쓰는 `SimLauncher-Unzip-<UUID>` 임시 폴더의 이름 등록과 삭제.
/// 폴더를 만들기 전에 이름을 등록하므로, 기기 목록 화면을 열 때 하는 정리가 지금 쓰는 폴더를 지우지 않는다.
final class ExtractionFolders: Sendable {
  static let prefix = "SimLauncher-Unzip-"

  private let temporaryDirectory: URL
  private let live = Mutex<Set<String>>([])

  init(temporaryDirectory: URL) {
    self.temporaryDirectory = temporaryDirectory
  }

  /// 새 폴더 이름 (`SimLauncher-Unzip-<UUID>`).
  static func newName() -> String {
    self.prefix + UUID().uuidString
  }

  func register(_ name: String) {
    _ = self.live.withLock { $0.insert(name) }
  }

  func unregister(_ name: String) {
    _ = self.live.withLock { $0.remove(name) }
  }

  /// 형식에 맞는 폴더면 지우고, 형식과 상관없이 이름 등록을 푼다. 실패는 무시한다 (다음에 기기 목록 화면을 열 때 다시 지운다).
  func remove(_ folder: URL) {
    if self.isExtractionFolder(folder) {
      Self.forceRemove(folder)
    }
    self.unregister(folder.lastPathComponent)
  }

  /// 임시 폴더에서 형식에 맞고 등록되지 않은 폴더를 지운다. 실패는 무시한다.
  func removeLeftovers() {
    guard
      let tmp = RealPath.of(self.temporaryDirectory),
      let names = try? FileManager.default.contentsOfDirectory(atPath: tmp)
    else {
      return
    }
    for name in names where Self.isExtractionName(name) {
      let folder = URL(filePath: tmp, directoryHint: .isDirectory).appending(path: name, directoryHint: .isDirectory)
      guard !self.live.withLock({ $0.contains(name) }), self.isExtractionFolder(folder) else {
        continue
      }
      Self.forceRemove(folder)
    }
  }

  /// 부모의 실제 경로가 임시 폴더의 실제 경로와 같고, 이름이 `SimLauncher-Unzip-<UUID>` 이며, 링크가 아닌 폴더다.
  /// 링크를 거르는 것은 권한 바꾸기가 링크 너머의 바깥 폴더를 바꾸지 않게 하기 위해서다.
  private func isExtractionFolder(_ folder: URL) -> Bool {
    guard
      Self.isExtractionName(folder.lastPathComponent),
      let parent = RealPath.of(folder.deletingLastPathComponent()),
      let tmp = RealPath.of(self.temporaryDirectory),
      parent == tmp,
      let type = try? folder.resourceValues(forKeys: [.fileResourceTypeKey]).fileResourceType
    else {
      return false
    }
    return type == .directory
  }

  private static func isExtractionName(_ name: String) -> Bool {
    name.hasPrefix(self.prefix) && UUID(uuidString: String(name.dropFirst(self.prefix.count))) != nil
  }

  /// zip 이 읽기·쓰기 권한 없는 폴더(0o555·0o111 등)를 만들 수 있어 `removeItem` 만으로는 지우지 못한다.
  /// 루트에 먼저 u+rwx 를 더하고, 폴더를 받을 때마다(그 폴더의 자식을 읽기 전에) 바로 u+rwx 를 더하며 훑은 뒤 지운다.
  /// 먼저 다 모은 뒤 바꾸면 읽을 수 없는 폴더 안의 폴더가 모이지 않는다. 링크는 따라가지도 바꾸지도 않는다.
  private static func forceRemove(_ folder: URL) {
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

  /// 링크를 따라가지 않고 소유자 읽기·쓰기·실행 권한을 더한다.
  private static func addOwnerPermissions(_ url: URL) {
    let path = url.path(percentEncoded: false)
    var info = stat()
    guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
      return
    }
    _ = chmod(path, (info.st_mode & 0o7777) | 0o700)
  }
}
