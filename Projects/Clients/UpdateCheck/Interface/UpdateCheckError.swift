/// 업데이트 확인 실패. 화면 문구는 Feature 가 케이스별로 정한다.
public enum UpdateCheckError: Error, Hashable, Sendable {
  /// 이 빌드에 배포 저장소가 없다 (요청하지 않았다).
  case notConfigured
  /// 인터넷에 연결되어 있지 않다 (`DownloadError.offline`).
  case offline
  /// 60초 안에 답이 없었다 (`DownloadError.timedOut`).
  case timedOut
  /// 서버에 연결하지 못했다: 호스트를 찾지 못함·연결 실패·연결 끊김·보안 연결 실패·https 아닌 리다이렉트.
  case connectionFailed
  /// HTTP 403·429: 프록시·방화벽 차단 또는 GitHub 의 요청 제한 (원인을 단정하지 않는다).
  case refused
  /// HTTP 404: 최신 정식 릴리스에 버전 파일이 없다, 또는 정식 릴리스가 없다·저장소가 없거나 비공개다.
  case notFound
  /// 그 밖의 2xx 아닌 HTTP 상태.
  case httpStatus(Int)
  /// 응답이 너무 크거나(64 KiB 초과), JSON 객체가 아니거나, `version` 이 없거나 문자열이 아니다.
  case unexpectedResponse
  /// 그 밖의 실패 (받기 실패·임시 저장 실패).
  case failed
  /// 호출한 Task 가 취소됐다.
  case cancelled

  /// 서버가 HTTP 로 답했다 (refused·notFound·httpStatus·unexpectedResponse). 자동 확인 기록 여부에 쓴다:
  /// 답했으면 기록해 하루 뒤 다시, 닿지 못했으면 기록하지 않고 한 시간 뒤 다시 시도한다.
  public var serverAnswered: Bool {
    switch self {
    case .refused, .notFound, .httpStatus, .unexpectedResponse:
      true
    case .notConfigured, .offline, .timedOut, .connectionFailed, .failed, .cancelled:
      false
    }
  }
}
