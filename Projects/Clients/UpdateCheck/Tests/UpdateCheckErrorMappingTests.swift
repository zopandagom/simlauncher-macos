import DownloadInterface
import Testing
import UpdateCheckInterface
@testable import UpdateCheckImpl

struct UpdateCheckErrorMappingTests {
  @Test(
    "DownloadError 모든 케이스의 매핑",
    arguments: [
      (DownloadError.offline, UpdateCheckError.offline),
      (.timedOut, .timedOut),
      (.hostNotFound, .connectionFailed),
      (.cannotConnect, .connectionFailed),
      (.connectionLost, .connectionFailed),
      (.secureConnectionFailed, .connectionFailed),
      (.insecureRedirect, .connectionFailed),
      (.httpStatus(403), .refused),
      (.httpStatus(429), .refused),
      (.httpStatus(404), .notFound),
      (.httpStatus(500), .httpStatus(500)),
      (.httpStatus(401), .httpStatus(401)),
      (.httpStatus(407), .httpStatus(407)),
      (.tooLarge, .unexpectedResponse),
      (.failed, .failed),
      (.insufficientDiskSpace, .failed),
      (.storageUnavailable, .failed),
      (.cancelled, .cancelled),
    ]
  )
  func maps(_ error: DownloadError, _ expected: UpdateCheckError) {
    #expect(UpdateCheckErrorMapping.map(error) == expected)
  }

  @Test(
    "serverAnswered: 서버가 HTTP 로 답한 실패만 참",
    arguments: [
      (UpdateCheckError.notConfigured, false),
      (.offline, false),
      (.timedOut, false),
      (.connectionFailed, false),
      (.refused, true),
      (.notFound, true),
      (.httpStatus(500), true),
      (.unexpectedResponse, true),
      (.failed, false),
      (.cancelled, false),
    ]
  )
  func serverAnswered(_ error: UpdateCheckError, _ expected: Bool) {
    #expect(error.serverAnswered == expected)
  }
}
