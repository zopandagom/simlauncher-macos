import Foundation

/// `DownloadClient.download(_:savingAs:onProgress:)` 가 받은 파일과 그 임시 폴더. `DownloadClient.removeDownloaded(_:)` 로 지운다.
public struct DownloadedFile: Hashable, Sendable {
  /// `<folder>/<DownloadedFileName>` (`download`·`download.apk`). 이름은 고정이고 서버가 준 이름을 쓰지 않는다. 일반 파일, 권한 0o600.
  public let file: URL
  /// 이번 받기가 만든 `SimLauncher-Download-<UUID>` 폴더 (0o700).
  public let folder: URL
  /// 받은 바이트 수 (= 파일 크기).
  public let byteCount: Int64
  /// 응답의 MIME 형식 (`text/html` 이면 로그인 화면 같은 웹 페이지를 받은 것일 수 있다). 없으면 nil.
  public let mimeType: String?

  public init(file: URL, folder: URL, byteCount: Int64, mimeType: String?) {
    self.file = file
    self.folder = folder
    self.byteCount = byteCount
    self.mimeType = mimeType
  }
}
