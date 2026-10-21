import DownloadInterface
import Foundation
import Testing
@testable import DownloadImpl

struct DownloadErrorMappingTests {
  static let codeCases: [(URLError.Code, DownloadError)] = [
    (.notConnectedToInternet, .offline),
    (.dataNotAllowed, .offline),
    (.internationalRoamingOff, .offline),
    (.cannotFindHost, .hostNotFound),
    (.dnsLookupFailed, .hostNotFound),
    (.cannotConnectToHost, .cannotConnect),
    (.timedOut, .timedOut),
    (.networkConnectionLost, .connectionLost),
    (.secureConnectionFailed, .secureConnectionFailed),
    (.serverCertificateHasBadDate, .secureConnectionFailed),
    (.serverCertificateUntrusted, .secureConnectionFailed),
    (.serverCertificateHasUnknownRoot, .secureConnectionFailed),
    (.serverCertificateNotYetValid, .secureConnectionFailed),
    (.clientCertificateRejected, .secureConnectionFailed),
    (.clientCertificateRequired, .secureConnectionFailed),
    (.appTransportSecurityRequiresSecureConnection, .insecureRedirect),
    (.httpTooManyRedirects, .failed),
    (.badURL, .failed),
    (.unsupportedURL, .failed),
    (.cancelled, .failed),
  ]

  @Test("URLError 코드 표 (-999 cancelled 는 호출자 취소가 아니므로 failed)", arguments: Self.codeCases)
  func mapCode(code: URLError.Code, expected: DownloadError) {
    #expect(DownloadErrorMapping.map(URLError(code)) == expected)
  }

  @Test("URLError 가 아닌 에러는 failed")
  func mapOtherError() {
    #expect(DownloadErrorMapping.map(CocoaError(.fileWriteUnknown)) == .failed)
    #expect(DownloadErrorMapping.map(CancellationError()) == .failed)
  }

  static let outOfSpaceErrors: [NSError] = [
    // 실측: 디스크가 찬 FileHandle 쓰기
    NSError(
      domain: NSCocoaErrorDomain,
      code: 640,
      userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 28)]
    ),
    NSError(domain: NSCocoaErrorDomain, code: 640),
    // open(2) 실패를 POSIXError 로 던진 모양
    POSIXError(.ENOSPC) as NSError,
    // 다른 Cocoa 코드 아래에만 POSIX 28
    NSError(
      domain: NSCocoaErrorDomain,
      code: 512,
      userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 28)]
    ),
  ]

  @Test("에러 사슬 어디든 Cocoa 640·POSIX 28 이 있으면 insufficientDiskSpace", arguments: Self.outOfSpaceErrors)
  func writeFailureOutOfSpace(error: NSError) {
    #expect(DownloadErrorMapping.writeFailure(error) == .insufficientDiskSpace)
  }

  static let otherWriteErrors: [NSError] = [
    POSIXError(.EACCES) as NSError,
    NSError(domain: NSCocoaErrorDomain, code: 512),
    NSError(
      domain: NSCocoaErrorDomain,
      code: 512,
      userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 13)]
    ),
  ]

  @Test("그 밖의 쓰기 실패는 storageUnavailable", arguments: Self.otherWriteErrors)
  func writeFailureOther(error: NSError) {
    #expect(DownloadErrorMapping.writeFailure(error) == .storageUnavailable)
  }

  @Test("여유: 중요 용도 여유가 0 보다 크면 그 값, 0·nil 이면 일반 여유, 둘 다 nil 이면 nil (실측 값)")
  func chooseCapacity() {
    #expect(DownloadErrorMapping.chooseCapacity(important: 319_260_182_732, plain: 311_251_709_952) == 319_260_182_732)
    #expect(DownloadErrorMapping.chooseCapacity(important: 0, plain: 20_262_912) == 20_262_912)
    #expect(DownloadErrorMapping.chooseCapacity(important: nil, plain: 20_262_912) == 20_262_912)
    #expect(DownloadErrorMapping.chooseCapacity(important: nil, plain: nil) == nil)
  }
}
