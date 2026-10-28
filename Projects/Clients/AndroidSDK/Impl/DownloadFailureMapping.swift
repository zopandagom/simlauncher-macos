import AndroidSDKInterface
import DownloadInterface

/// `DownloadError` → `AndroidDownloadFailure`. `.cancelled` 는 부르는 쪽이 따로 다루므로 nil.
enum DownloadFailureMapping {
  static func failure(_ error: DownloadError) -> AndroidDownloadFailure? {
    switch error {
    case .insecureRedirect: .insecureRedirect
    case let .httpStatus(status): .httpStatus(status)
    case .offline, .hostNotFound, .cannotConnect, .timedOut, .connectionLost, .secureConnectionFailed:
      self.connectionFailure(error)
    case .insufficientDiskSpace, .tooLarge, .storageUnavailable, .failed: self.storageFailure(error)
    case .cancelled: nil
    }
  }

  /// 연결 실패. `failure` 가 연결 실패만 넘긴다.
  private static func connectionFailure(_ error: DownloadError) -> AndroidDownloadFailure {
    switch error {
    case .offline: .offline
    case .hostNotFound: .hostNotFound
    case .cannotConnect: .cannotConnect
    case .timedOut: .timedOut
    case .connectionLost: .connectionLost
    case .secureConnectionFailed: .secureConnectionFailed
    default: .failed
    }
  }

  /// 저장·크기·그 밖의 실패. `failure` 가 이 경우만 넘긴다.
  private static func storageFailure(_ error: DownloadError) -> AndroidDownloadFailure {
    switch error {
    case .insufficientDiskSpace: .insufficientDiskSpace
    case .tooLarge: .tooLarge
    case .storageUnavailable: .storageUnavailable
    default: .failed
    }
  }
}
