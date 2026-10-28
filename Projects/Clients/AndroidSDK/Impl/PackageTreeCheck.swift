import Foundation

/// 심볼릭 링크를 끝까지 푼 실제 경로 (`realpath(3)`). 대상이 없거나 루프면 nil (AppBundle Impl 의 `RealPath` 와 같다.
/// Impl 끼리 import 할 수 없어 복제한다). `URL.resolvingSymlinksInPath()` 는 대상 없는 링크면 링크 경로를 그대로 돌려줘 쓰지 않는다.
enum RealPath {
  static func of(_ url: URL) -> String? {
    self.of(url.path(percentEncoded: false))
  }

  static func of(_ path: String) -> String? {
    guard let resolved = realpath(path, nil) else {
      return nil
    }
    defer { free(resolved) }
    return String(cString: resolved)
  }

  /// `path` 가 `base` 와 같거나 `base` 아래에 있다.
  static func isWithin(_ path: String, _ base: String) -> Bool {
    path == base || path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
  }
}

/// 푼 뒤 실제 파일 검사. 최종 경로로 옮길지는 이 검사로 정한다 (풀기 전 목록은 속일 수 있다).
enum PackageTreeCheck {
  /// 첫 실패에서 멈춘다: 맨 위 항목(`__MACOSX` 무시) → 링크의 실제 경로. 맨 위 폴더의 실제 경로를 돌려준다.
  /// - 맨 위 폴더가 없다(빈 트리·파일 하나) → `.unreadable`. 맨 위 항목이 둘 이상이거나 맨 위가 링크 → `.unsafe`.
  /// - 그 아래 링크가 대상 없음·루프이거나 맨 위 폴더 밖을 가리키면 `.unsafe`.
  /// - 트리를 읽다 오류가 나면 `.unreadable`.
  static func check(contents: URL) throws(PackageArchiveFailure) -> URL {
    guard let root = RealPath.of(contents) else {
      throw .unreadable
    }
    let top = try Self.topFolder(in: URL(filePath: root, directoryHint: .isDirectory))
    guard let topReal = RealPath.of(top) else {
      throw .unreadable
    }
    for link in try Self.symlinks(under: top) {
      guard let target = RealPath.of(link), RealPath.isWithin(target, topReal) else {
        throw .unsafe
      }
    }
    return URL(filePath: topReal, directoryHint: .isDirectory)
  }

  private static func topFolder(in root: URL) throws(PackageArchiveFailure) -> URL {
    let items: [URL]
    do {
      items = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.fileResourceTypeKey],
        options: []
      )
    } catch {
      throw .unreadable
    }
    let candidates = items.filter { $0.lastPathComponent != "__MACOSX" }
    guard candidates.count <= 1 else {
      throw .unsafe
    }
    guard let item = candidates.first else {
      throw .unreadable
    }
    guard let type = try? item.resourceValues(forKeys: [.fileResourceTypeKey]).fileResourceType else {
      throw .unreadable
    }
    switch type {
    case .directory: return item
    case .symbolicLink: throw .unsafe
    default: throw .unreadable
    }
  }

  /// 링크를 따라가지 않고 훑으며 모은 심볼릭 링크.
  private static func symlinks(under root: URL) throws(PackageArchiveFailure) -> [URL] {
    var failed = false
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.fileResourceTypeKey],
      options: [],
      errorHandler: { _, _ in
        failed = true
        return false
      }
    ) else {
      throw .unreadable
    }
    var links: [URL] = []
    for case let url as URL in enumerator {
      guard let type = try? url.resourceValues(forKeys: [.fileResourceTypeKey]).fileResourceType else {
        throw .unreadable
      }
      if type == .symbolicLink {
        links.append(url)
      }
    }
    if failed {
      throw .unreadable
    }
    return links
  }
}
