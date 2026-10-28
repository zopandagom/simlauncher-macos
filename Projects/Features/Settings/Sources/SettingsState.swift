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

/// 설정 창에서 고른 Android SDK 폴더의 판정 결과 줄. 저장했는지는 `candidate.shouldSave(writable:)` 로 정해진다.
/// 판정 뒤 저장하려는데 바깥에서 잠겼으면 결과 줄을 남기지 않는다 (다시 읽어 잠금 안내로 한 번만 보인다).
public struct SettingsSDKFolderResult: Hashable, Sendable {
  /// 고른 폴더의 경로 (링크를 풀지 않은 값).
  public let path: String
  public let candidate: AndroidSDKFolderCandidate
  /// 고른 폴더(이미 있으면 `system-images` 도)에 쓸 수 있다.
  public let writable: Bool

  public init(path: String, candidate: AndroidSDKFolderCandidate, writable: Bool) {
    self.path = path
    self.candidate = candidate
    self.writable = writable
  }

  /// 저장했다: SDK 폴더는 쓸 수 없어도, 빈 폴더는 쓸 수 있을 때만.
  public var isSaved: Bool {
    self.candidate.shouldSave(writable: self.writable)
  }
}
