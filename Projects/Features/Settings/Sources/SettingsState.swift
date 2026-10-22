import Core
import DownloadInterface

/// 입력란 아래 안내할 문제.
public enum CatalogDraftProblem: Hashable, Sendable {
  /// 주소 검사에 걸렸다. 빈 입력(`.empty`)은 안내 없이 버튼만 비활성이라 `SettingsModel.draftProblem` 이 돌려주지 않는다.
  case url(DownloadURLProblem)
  /// 이미 등록된 카탈로그와 같다 (`DownloadURL.comparisonKey`).
  case duplicate
}

/// 마지막 등록 결과 줄.
public enum CatalogRegistrationResult: Hashable, Sendable {
  /// 등록했다. `raw` 는 저장한 문자열, `appCount` 는 확인 때 읽은 카탈로그의 앱 수 (안내용).
  case added(raw: String, appCount: Int)
  case failed(CatalogRegistrationFailure)
}

/// 등록하지 않은 이유. 확인 중 바깥에서 잠김·같은 카탈로그가 들어온 경우는 결과 줄로 남기지 않는다
/// (목록을 다시 읽어 잠금 안내·중복 캡션으로 한 번만 보인다).
public enum CatalogRegistrationFailure: Hashable, Sendable {
  /// 받지 못했다. `.cancelled` 는 결과로 남기지 않는다.
  case download(DownloadError)
  /// 받은 파일이 카탈로그 규격(docs/CATALOG.md)에 맞지 않는다.
  case catalog(BuildCatalogProblem)
}
