import Foundation
import Synchronization

/// `download(_:onProgress:)` 이 쓰는 `SimLauncher-Download-<UUID>` 임시 폴더의 이름 등록과 삭제.
/// 폴더를 만들기 전에 이름을 등록하므로, 남은 폴더 정리가 지금 받는 중인 폴더를 지우지 않는다.
/// 등록은 이 프로세스 안에서만 유효하다.
final class DownloadFolders: Sendable {
  static let prefix = "SimLauncher-Download-"
  /// 폴더 안의 받은 파일 이름. 서버가 준 이름을 쓰지 않는다.
  static let fileName = "download"

  private let temporaryDirectory: URL
  private let live = Mutex<Set<String>>([])

  init(temporaryDirectory: URL) {
    self.temporaryDirectory = temporaryDirectory
  }

  /// 새 폴더 이름 (`SimLauncher-Download-<UUID>`).
  static func newName() -> String {
    self.prefix + UUID().uuidString
  }

  func register(_ name: String) {
    _ = self.live.withLock { $0.insert(name) }
  }

  func unregister(_ name: String) {
    _ = self.live.withLock { $0.remove(name) }
  }

  /// 형식에 맞는 폴더면 지우고, 형식과 상관없이 이름 등록을 푼다. 실패는 무시한다 (다음 남은 폴더 정리가 다시 지운다).
  func remove(_ folder: URL) {
    if self.isDownloadFolder(folder) {
      try? FileManager.default.removeItem(at: folder)
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
    for name in names where Self.isDownloadName(name) {
      let folder = URL(filePath: tmp, directoryHint: .isDirectory).appending(path: name, directoryHint: .isDirectory)
      guard !self.live.withLock({ $0.contains(name) }), self.isDownloadFolder(folder) else {
        continue
      }
      try? FileManager.default.removeItem(at: folder)
    }
  }

  /// 부모의 실제 경로가 임시 폴더의 실제 경로와 같고, 이름이 `SimLauncher-Download-<UUID>` 이며, 링크가 아닌 폴더다.
  /// 안에는 우리가 만든 파일 하나뿐이라 권한을 바꾸며 훑지 않고 `removeItem` 으로 지운다.
  private func isDownloadFolder(_ folder: URL) -> Bool {
    guard
      Self.isDownloadName(folder.lastPathComponent),
      let parent = RealPath.of(folder.deletingLastPathComponent()),
      let tmp = RealPath.of(self.temporaryDirectory),
      parent == tmp,
      let type = try? folder.resourceValues(forKeys: [.fileResourceTypeKey]).fileResourceType
    else {
      return false
    }
    return type == .directory
  }

  private static func isDownloadName(_ name: String) -> Bool {
    name.hasPrefix(self.prefix) && UUID(uuidString: String(name.dropFirst(self.prefix.count))) != nil
  }
}
