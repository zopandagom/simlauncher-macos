import DownloadInterface
import Foundation

/// 테스트·Example 이 함께 쓰는 받기 결과. 고정 경로라 실제로 읽지 않는 Fake 에서만 쓴다.
public extension DownloadedFile {
  /// folder `/tmp/SimLauncher-Download-Fake-<index>/`, file `<folder>/<name>` (기본 `download`), 1024 바이트,
  /// `application/zip`. 파일은 만들지 않는다.
  static func fake(index: Int, name: DownloadedFileName = .download) -> DownloadedFile {
    let folder = URL(filePath: "/tmp/SimLauncher-Download-Fake-\(index)", directoryHint: .isDirectory)
    return DownloadedFile(
      file: folder.appending(path: name.rawValue, directoryHint: .notDirectory),
      folder: folder,
      byteCount: 1024,
      mimeType: "application/zip"
    )
  }
}
