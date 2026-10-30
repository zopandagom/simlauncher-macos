import Foundation

/// `inspect` 가 쓰는 `SimLauncher-APK-<UUID>` 임시 폴더. 안에는 apk 의 실제 경로를 가리키는 고정 이름 링크 `source.apk` 하나뿐이다.
/// 강제 종료로 남아도 내용이 없으므로 남은 폴더 정리는 두지 않는다 (iOS `SimLauncher-Unzip-*` 정리와 다른 점).
struct InspectionFolder {
  static let prefix = "SimLauncher-APK-"
  static let linkName = "source.apk"

  let folder: URL
  /// zipinfo·unzip 에 넘기는 고정 이름 링크.
  let link: URL

  /// 새 폴더(0o700, 중간 폴더는 만들지 않음)와 링크를 만든다. 실패하면 만든 폴더를 지우고 nil.
  /// - Parameter temporaryDirectory: 실제 경로로 바꿔 쓴다.
  static func make(in temporaryDirectory: URL, linkingTo target: String) -> InspectionFolder? {
    guard let tmp = RealPath.of(temporaryDirectory) else {
      return nil
    }
    let folder = URL(filePath: tmp, directoryHint: .isDirectory)
      .appending(path: self.prefix + UUID().uuidString, directoryHint: .isDirectory)
    let link = folder.appending(path: self.linkName, directoryHint: .notDirectory)
    do {
      try FileManager.default.createDirectory(
        at: folder,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
    } catch {
      return nil
    }
    do {
      try FileManager.default.createSymbolicLink(atPath: link.path(percentEncoded: false), withDestinationPath: target)
    } catch {
      try? FileManager.default.removeItem(at: folder)
      return nil
    }
    return InspectionFolder(folder: folder, link: link)
  }

  /// 이름이 `SimLauncher-APK-<UUID>` 이고 링크가 아닌 폴더면 지운다 (링크는 따라가지 않고 링크만 지운다). 실패는 무시한다.
  func remove() {
    let name = self.folder.lastPathComponent
    guard
      name.hasPrefix(Self.prefix),
      UUID(uuidString: String(name.dropFirst(Self.prefix.count))) != nil,
      (try? self.folder.resourceValues(forKeys: [.fileResourceTypeKey]).fileResourceType) == .directory
    else {
      return
    }
    try? FileManager.default.removeItem(at: self.folder)
  }
}
