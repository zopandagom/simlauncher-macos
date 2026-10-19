import AppBundleInterface
import Foundation

/// 심볼릭 링크를 끝까지 푼 실제 경로 (`realpath(3)`). 대상이 없거나 루프면 nil.
/// `URL.resolvingSymlinksInPath()` 는 대상 없는 링크면 링크 경로를 그대로 돌려줘 검사가 통과해 버리므로 쓰지 않는다.
enum RealPath {
  static func of(_ url: URL) -> String? {
    guard let resolved = realpath(url.path(percentEncoded: false), nil) else {
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

/// 푼 뒤 실제 파일 검사. 설치할지는 이 검사로 정한다 (풀기 전 목록은 속일 수 있다). 크기·항목 수는 세지 않는다.
enum ExtractedTreeCheck {
  /// 첫 실패에서 멈춘다: 트리 훑기 → 맨 위 .app 개수 → 링크의 실제 경로. 맨 위 .app 의 실제 경로를 돌려준다.
  /// - 맨 위에서 `__MACOSX`·`._*` 와 .app 이 아닌 항목은 무시한다. .app 이름인 링크는 `.zipUnsafeEntry`, 파일은 세지 않는다.
  /// - 링크가 대상 없음·루프이거나, .app 안의 링크가 .app 밖을, 그 밖의 링크가 `contents` 밖을 가리키면 `.zipUnsafeEntry`.
  /// - 트리를 읽다 오류가 나면(읽을 수 없는 폴더 등) `.zipUnreadable`.
  static func check(contents: URL) throws(AppBundleError) -> URL {
    guard let root = RealPath.of(contents) else {
      throw .zipUnreadable
    }
    let rootURL = URL(filePath: root, directoryHint: .isDirectory)
    let links = try Self.symlinks(under: rootURL)
    let app = try Self.topLevelApp(in: rootURL)
    guard let appReal = RealPath.of(app) else {
      throw .zipUnsafeEntry
    }
    for link in links {
      guard let target = RealPath.of(link) else {
        throw .zipUnsafeEntry
      }
      let base = RealPath.isWithin(link.path(percentEncoded: false), appReal + "/") ? appReal : root
      guard RealPath.isWithin(target, base) else {
        throw .zipUnsafeEntry
      }
    }
    return URL(filePath: appReal, directoryHint: .isDirectory)
  }

  /// 링크를 따라가지 않고 훑으며 모은 심볼릭 링크.
  private static func symlinks(under root: URL) throws(AppBundleError) -> [URL] {
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
      throw .zipUnreadable
    }
    var links: [URL] = []
    for case let url as URL in enumerator {
      guard let type = try? url.resourceValues(forKeys: [.fileResourceTypeKey]).fileResourceType else {
        throw .zipUnreadable
      }
      if type == .symbolicLink {
        links.append(url)
      }
    }
    if failed {
      throw .zipUnreadable
    }
    return links
  }

  /// 맨 위 .app 폴더 하나. 이름은 `ZipNames.isAppName`.
  private static func topLevelApp(in root: URL) throws(AppBundleError) -> URL {
    let items: [URL]
    do {
      items = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.fileResourceTypeKey],
        options: []
      )
    } catch {
      throw .zipUnreadable
    }
    var apps: [URL] = []
    for item in items {
      let name = item.lastPathComponent
      guard !ZipNames.isMetadata(name), ZipNames.isAppName(name) else {
        continue
      }
      guard let type = try? item.resourceValues(forKeys: [.fileResourceTypeKey]).fileResourceType else {
        throw .zipUnreadable
      }
      if type == .symbolicLink {
        throw .zipUnsafeEntry
      }
      if type == .directory {
        apps.append(item)
      }
    }
    guard let app = apps.first else {
      throw .zipWithoutApp
    }
    guard apps.count == 1 else {
      throw .zipWithMultipleApps
    }
    return app
  }
}
