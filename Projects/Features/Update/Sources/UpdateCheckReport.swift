import Core
import UpdateCheckInterface

/// 업데이트 확인 창의 단계. 창이 보이지 않을 때는 `UpdateModel.manualCheck` 가 nil 이다.
public enum UpdateCheckPhase: Hashable, Sendable {
  /// 확인 중 (진행 중인 요청에 합류했을 수도 있다).
  case checking
  /// 확인이 끝났다.
  case finished(UpdateCheckReport)
}

/// 업데이트 확인 창에 보일 결과. 버전은 숫자 버전으로 해석된 값만 담는다 (응답 원문 문자열은 담지 않는다).
public enum UpdateCheckReport: Hashable, Sendable {
  /// 지금보다 높은 버전이 있다. `skipped` 면 "이 버전 건너뛰기" 로 자동 알림(배너)에서 뺀 버전이다.
  case newer(AppVersion, current: AppVersion, skipped: Bool)
  /// 최신이다 (같거나 지금이 더 높다).
  case upToDate(current: AppVersion)
  /// 이 앱의 버전을 읽지 못해 비교하지 못했다.
  case currentUnknown
  /// 최신 릴리스의 버전 값이 숫자 버전이 아니라 비교하지 못했다.
  case latestUnrecognized
  /// 확인하지 못했다.
  case failed(UpdateCheckError)
}
