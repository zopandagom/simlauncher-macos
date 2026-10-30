import Core
import DownloadInterface

extension DownloadClient {
  /// `download(_:savingAs:onProgress:)` 의 결과를 값으로 돌려준다. Model 이 소유한 받기 Task 가 던지지 않게 감싼다
  /// (Task 클로저 안에서는 catch 의 에러 타입이 any Error 로 추론되므로 여기서 타입을 정한다). Launcher 의 같은 도우미와 같다.
  func downloadResult(
    _ url: DownloadURL,
    savingAs name: DownloadedFileName,
    onProgress: @escaping @Sendable (DownloadProgress) async -> Void
  ) async -> Result<DownloadedFile, DownloadError> {
    do throws(DownloadError) {
      return try await .success(self.download(url, savingAs: name, onProgress: onProgress))
    } catch {
      return .failure(error)
    }
  }
}
