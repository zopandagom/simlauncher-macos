import Foundation

/// 인증 challenge 에 어떻게 답할지. delegate 가 `.performDefaultHandling`·`.rejectProtectionSpace` 로 바꾼다
/// (테스트가 URLSession 타입 이름을 쓰지 않게 따로 둔다).
enum ChallengeAnswer: Equatable, Sendable {
  case defaultHandling
  case reject
}

/// 인증 challenge 판정. 인증은 지원하지 않는다.
enum ChallengePolicy {
  /// 서버 신뢰(`NSURLAuthenticationMethodServerTrust`)만 기본 처리(시스템 신뢰 확인), 그 밖(Basic·Digest·Negotiate·NTLM·
  /// 클라이언트 인증서·모르는 방식)은 거절. 거절하면 401 같은 응답으로 끝나고 자격 증명은 보내지 않는다.
  static func answer(forAuthenticationMethod method: String) -> ChallengeAnswer {
    method == NSURLAuthenticationMethodServerTrust ? .defaultHandling : .reject
  }
}
