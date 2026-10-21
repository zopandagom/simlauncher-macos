import Foundation
import Testing
@testable import DownloadImpl

struct ChallengePolicyTests {
  @Test("서버 신뢰 확인만 기본 처리한다")
  func serverTrust() {
    #expect(ChallengePolicy.answer(forAuthenticationMethod: NSURLAuthenticationMethodServerTrust) == .defaultHandling)
  }

  @Test(
    "그 밖의 인증 요구(Basic·Digest·Negotiate·NTLM·클라이언트 인증서·모르는 방식)는 거절한다",
    arguments: [
      NSURLAuthenticationMethodHTTPBasic,
      NSURLAuthenticationMethodHTTPDigest,
      NSURLAuthenticationMethodNegotiate,
      NSURLAuthenticationMethodNTLM,
      NSURLAuthenticationMethodClientCertificate,
      NSURLAuthenticationMethodDefault,
      "UnknownMethod",
    ]
  )
  func reject(method: String) {
    #expect(ChallengePolicy.answer(forAuthenticationMethod: method) == .reject)
  }
}
