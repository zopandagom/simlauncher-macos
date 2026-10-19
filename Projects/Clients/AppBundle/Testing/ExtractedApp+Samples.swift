import AppBundleInterface
import Foundation

/// 테스트·Example 이 함께 쓰는 풀기 결과. 고정 경로라 실제로 읽지 않는 Fake 에서만 쓴다.
public extension ExtractedApp {
  /// folder `/tmp/SimLauncher-Unzip-Fake-<index>/`, app `<folder>/contents/Sample.app`. 파일은 만들지 않는다.
  static func fake(index: Int) -> ExtractedApp {
    let folder = URL(filePath: "/tmp/SimLauncher-Unzip-Fake-\(index)", directoryHint: .isDirectory)
    return ExtractedApp(
      app: folder.appending(path: "contents/Sample.app", directoryHint: .isDirectory),
      folder: folder
    )
  }
}
