import Core

/// 사용자 설정 (UserDefaults 표준 도메인 = 앱 번들 ID). 설정 저장은 이 Client 의 Impl 에서만 한다
/// (lint `preferences_only_in_preferences_impl`). 관리자가 `defaults write`·MDM 으로 미리 넣은 값도 같은 도메인·키라 그대로 읽는다.
/// 관리자가 강제한 키(구성 프로필 등, `objectIsForced`)는 잠김이고 쓰지 않는다. 모든 메서드는 동기이고 빠르다
/// (UserDefaults 는 프로세스 안 캐시라 async 로 두면 Model 의 await 지점만 는다).
public protocol PreferencesClient: Sendable {
  /// 카탈로그 주소 목록(저장 순서)과 잠금 여부. 키가 없으면 빈 목록.
  func catalogURLs() -> CatalogURLSetting

  /// 최신 목록을 다시 읽어, 잠겼으면 `.locked`, 같은 카탈로그(Core `CatalogURLList.indexOfSameCatalog`)가 있으면 `.duplicate`,
  /// 아니면 `CatalogURLList.storedString(for:)` 를 끝에 붙여 저장하고 저장 뒤 목록을 돌려준다.
  func addCatalogURL(_ url: DownloadURL) throws(PreferencesError) -> CatalogURLSetting

  /// 최신 목록을 다시 읽어, 잠겼으면 `.locked`, 아니면 `raw` 와 같은 문자열을 모두 빼고 저장한 뒤 목록을 돌려준다
  /// (같은 문자열이 없으면 저장하지 않고 그대로 돌려준다).
  func removeCatalogURL(_ raw: String) throws(PreferencesError) -> CatalogURLSetting
}
