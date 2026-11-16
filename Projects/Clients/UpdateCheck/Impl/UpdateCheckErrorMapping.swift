import DownloadInterface
import UpdateCheckInterface

/// 받기 실패를 업데이트 확인 실패로 바꾸는 규칙. 모든 `DownloadError` 케이스를 빠짐없이 정한다.
enum UpdateCheckErrorMapping {
  static func map(_ error: DownloadError) -> UpdateCheckError {
    switch error {
    case .offline:
      .offline
    case .timedOut:
      .timedOut
    case .hostNotFound, .cannotConnect, .connectionLost, .secureConnectionFailed, .insecureRedirect:
      .connectionFailed
    case .httpStatus(403), .httpStatus(429):
      // 403 은 회사 프록시·방화벽 차단이, 429 는 GitHub 의 요청 제한이 쓸 수 있다. 원인을 단정하지 않는다.
      .refused
    case .httpStatus(404):
      .notFound
    case let .httpStatus(code):
      .httpStatus(code)
    case .tooLarge:
      .unexpectedResponse
    case .failed, .insufficientDiskSpace, .storageUnavailable:
      .failed
    case .cancelled:
      .cancelled
    }
  }
}
