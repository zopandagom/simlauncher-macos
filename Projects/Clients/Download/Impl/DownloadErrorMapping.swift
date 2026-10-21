import DownloadInterface
import Foundation

/// 전송·파일 오류를 `DownloadError` 로 바꾸는 규칙과 여유 공간 고르기. 한 곳에서 정한다.
enum DownloadErrorMapping {
  /// 전송이 오류로 끝났을 때. `URLError` 면 코드로 정하고, 아니면 `.failed`.
  /// -999 cancelled 는 `.failed` 다: 우리가 부른 cancel 은 모두 먼저 실패로 기록되고 사용자 취소는 Task 취소로
  /// `.cancelled` 가 되므로, 여기까지 오는 -999 는 예상 밖 경로(세션 무효화 등)다.
  static func map(_ error: any Error) -> DownloadError {
    guard let error = error as? URLError else {
      return .failed
    }
    switch error.code {
    case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
      return .offline
    case .cannotFindHost, .dnsLookupFailed:
      return .hostNotFound
    case .cannotConnectToHost:
      return .cannotConnect
    case .timedOut:
      return .timedOut
    case .networkConnectionLost:
      return .connectionLost
    case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
         .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
         .clientCertificateRequired:
      return .secureConnectionFailed
    case .appTransportSecurityRequiresSecureConnection:
      return .insecureRedirect
    default:
      return .failed
    }
  }

  /// 임시 폴더·파일을 만들거나 쓰다가 실패했을 때. 에러와 그 `NSUnderlyingErrorKey` 사슬 중 하나라도
  /// (NSCocoaErrorDomain, 640 fileWriteOutOfSpace) 이거나 (NSPOSIXErrorDomain, 28 ENOSPC) 면 `.insufficientDiskSpace`,
  /// 아니면 `.storageUnavailable`. 디스크가 찬 `FileHandle` 쓰기는 Cocoa 640 아래 POSIX 28 로 온다.
  static func writeFailure(_ error: any Error) -> DownloadError {
    var current: NSError? = error as NSError
    while let error = current {
      if Self.isOutOfSpace(error) {
        return .insufficientDiskSpace
      }
      current = error.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return .storageUnavailable
  }

  /// 디스크 여유. 중요 용도 여유가 0 보다 크면 그 값, 0 이거나 읽지 못하면 일반 여유, 둘 다 없으면 nil (비교를 건너뜀).
  /// 붙인 디스크 이미지 볼륨은 중요 용도 여유가 0 으로 읽혀, 그것만 쓰면 여유가 있어도 모든 받기를 거절한다.
  static func chooseCapacity(important: Int64?, plain: Int?) -> Int64? {
    if let important, important > 0 {
      return important
    }
    return plain.map { Int64($0) }
  }

  private static func isOutOfSpace(_ error: NSError) -> Bool {
    (error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileWriteOutOfSpace.rawValue)
      || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOSPC))
  }
}
