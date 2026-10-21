/// 받기 실패. 화면 문구는 Feature 가 케이스별로 정한다.
public enum DownloadError: Error, Hashable, Sendable {
  /// https 가 아닌 주소로 리다이렉트됐다. 따라가지 않는다 (요청을 보내지 않음).
  /// ATS 가 막은 경우(-1022 appTransportSecurityRequiresSecureConnection)도 여기 든다.
  case insecureRedirect
  /// 마지막 응답의 HTTP 상태가 2xx 가 아니다 (404·500·401 등). 본문은 받지 않는다.
  /// 401 처럼 서버가 인증을 요구하면 응하지 않고 `.httpStatus(401)` 로 끝난다 (인증은 지원하지 않는다).
  case httpStatus(Int)
  /// 인터넷에 연결되어 있지 않다: -1009 notConnectedToInternet, -1020 dataNotAllowed, -1018 internationalRoamingOff.
  case offline
  /// 호스트 이름을 찾지 못했다: -1003 cannotFindHost, -1006 dnsLookupFailed.
  case hostNotFound
  /// 서버에 연결하지 못했다 (닫힌 포트 등): -1004 cannotConnectToHost.
  case cannotConnect
  /// 응답이 60초 동안 오지 않았다 (연결 전·본문 중 모두): -1001 timedOut. `fetchData` 는 전체 60초를 넘겨도.
  case timedOut
  /// 받는 중 연결이 끊겼다: -1005 networkConnectionLost, 또는 정상 종료인데 받은 크기가 Content-Length 보다 작다.
  case connectionLost
  /// 보안 연결(TLS) 실패: -1200 secureConnectionFailed, -1201~-1206 인증서 문제(-1202 untrusted 등).
  case secureConnectionFailed
  /// Content-Length 가 임시 폴더 볼륨의 여유보다 크다, 또는 임시 폴더·파일을 만들거나 쓰다가 디스크가 찼다 (ENOSPC).
  case insufficientDiskSpace
  /// `fetchData` 만: Content-Length 나 받은 바이트가 `maxBytes` 를 넘었다.
  case tooLarge
  /// 호출한 Task 가 취소됐다 (그때만). 받던 파일·폴더는 지운 뒤 던진다.
  case cancelled
  /// 임시 폴더·파일을 만들지 못했다, 쓰기에 실패했다 (디스크 부족은 제외).
  case storageUnavailable
  /// 그 밖의 실패 (-1007 리다이렉트가 너무 많음, -1000 badURL, -1002 unsupportedURL, 응답이 HTTP 가 아님,
  /// 호출자가 취소하지 않았는데 전송이 -999 cancelled 로 끝남 등).
  case failed
}
