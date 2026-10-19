import Foundation

/// zip 에서 푼 .app 과 그 임시 폴더. `AppBundleClient.removeExtracted(_:)` 로 지운다.
public struct ExtractedApp: Hashable, Sendable {
  /// 풀린 .app 의 실제 경로(realpath). 폴더이고 링크가 아니다.
  public let app: URL
  /// 이번 풀기가 만든 `SimLauncher-Unzip-<UUID>` 폴더.
  public let folder: URL

  public init(app: URL, folder: URL) {
    self.app = app
    self.folder = folder
  }
}
