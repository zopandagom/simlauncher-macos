import Core
import Foundation

/// 사용자 설정 (UserDefaults 표준 도메인 = 앱 번들 ID): 빌드 카탈로그 주소 목록(`CatalogURLs`), Android SDK 위치(`AndroidSDKPath`),
/// 동의한 Android SDK 라이선스 원문의 지문(`AcceptedAndroidLicenses`), 저장한 로그 필터(`LogFilters`), 새 버전 자동 확인(`AutomaticUpdateCheck`),
/// 앱이 쓰는 업데이트 기록(건너뛴 버전 `SkippedUpdateVersion`, 마지막 확인 시각 `LastUpdateCheck`, 배너 숨김 `DismissedUpdateBanner`,
/// 받은 최신 버전 `LatestKnownUpdateVersion`).
/// 설정 저장은 이 Client 의 Impl 에서만 한다 (lint `preferences_only_in_preferences_impl`). 관리자가 `defaults write`·MDM 으로 미리 넣은 값도
/// 같은 도메인·키라 그대로 읽는다.
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

  /// Android SDK 위치 (키 `AndroidSDKPath`, 문자열). 키가 없으면 `.absent`, 문자열이 아니면 `.malformed`. 형식 검사는 하지 않는다
  /// (Core `AndroidSDKRootChoice.resolve`).
  func androidSDKPath() -> AndroidSDKPathSetting

  /// nil 이면 키를 지운다 (기본 위치). 잠겼으면 `.locked` 이고 쓰지 않는다. 문자열은 그대로 저장한다 (판정은 부르는 쪽).
  func setAndroidSDKPath(_ path: String?) throws(PreferencesError)

  /// 동의한 Android SDK 라이선스 원문의 지문(`AndroidLicense.fingerprint`). 키 `AcceptedAndroidLicenses`(문자열 배열).
  /// 키가 없거나 배열이 아니면 빈 집합, 배열이면 문자열 항목만. 관리자가 강제해 넣은 지문도 그대로 읽는다 (그 원문은 묻지 않는다).
  func acceptedAndroidLicenses() -> Set<String>

  /// 최신 값을 다시 읽어 없는 지문만 더해 저장한다 (더할 것이 없으면 쓰지 않는다). 잠겼으면 `.locked` 이고 쓰지 않는다.
  func addAcceptedAndroidLicenses(_ fingerprints: Set<String>) throws(PreferencesError)

  /// 저장된 로그 필터(키 `LogFilters`, 사전 배열)의 읽은 항목과 잠금 여부. 키가 없거나 배열이 아니면 빈 목록.
  /// 읽을 수 없는 항목은 목록에 없다 (docs/CATALOG.md 9절).
  func savedLogFilters() -> SavedLogFilterSetting

  /// 최신 값을 다시 읽어 잠겼으면 `.locked`. 같은 이름(대소문자 무시)이 있으면 `replacingSameName` 이 거짓이면 `.duplicate`,
  /// 참이면 그 자리를 바꾼다(이름 표기도 새 값). 없으면 보이는 목록이 상한이면 `.limitReached`, 아니면 끝에 붙인다.
  /// 읽을 수 없는 항목은 같은 자리에 그대로 둔다. 저장 뒤 목록을 돌려준다 (Core `SavedLogFilterList.saveChange`).
  func saveLogFilter(_ filter: SavedLogFilter, replacingSameName: Bool) throws(PreferencesError)
    -> SavedLogFilterSetting

  /// 최신 값을 다시 읽어 잠겼으면 `.locked`, 아니면 같은 이름(대소문자 무시)의 읽은 항목을 모두 지운다
  /// (없으면 쓰지 않는다). 읽을 수 없는 항목은 그대로 둔다. 지운 뒤 목록을 돌려준다.
  func removeLogFilter(named name: String) throws(PreferencesError) -> SavedLogFilterSetting

  /// 새 버전 자동 확인 (키 `AutomaticUpdateCheck`)과 잠금 여부. 키 없음 → 켬. Bool(숫자 0·1 포함) → 그 값,
  /// 문자열이면 대소문자 무시 `yes`·`true`·`1` → 켬, `no`·`false`·`0` → 끔, 그 밖의 값 → 끔 (강제 값도 같다).
  func automaticUpdateCheck() -> AutomaticUpdateCheckSetting

  /// 잠겼으면 `.locked` 이고 쓰지 않는다. 끄기·켜기 모두 Bool 로 쓴다 (키를 지우지 않는다: 지우면 /Library/Preferences 값이 다시 보인다).
  func setAutomaticUpdateCheck(_ isEnabled: Bool) throws(PreferencesError)

  /// 건너뛴 버전 (키 `SkippedUpdateVersion`, `AppVersion.description` 문자열). 문자열이 아니면 nil. 해석은 부르는 쪽이 한다.
  func skippedUpdateVersion() -> String?

  /// 잠겼으면 `.locked` 이고 쓰지 않는다.
  func setSkippedUpdateVersion(_ version: String) throws(PreferencesError)

  /// 서버가 답한 마지막 업데이트 확인의 시각 (키 `LastUpdateCheck`, 날짜). 날짜가 아니면 nil.
  func lastUpdateCheck() -> Date?

  /// 잠겼으면 쓰지 않는다 (던지지 않는다: 기록 실패는 자동 확인이 재시도 간격으로 한 번 더 할 뿐이다).
  func setLastUpdateCheck(_ date: Date)

  /// 배너 숨김 (키 `DismissedUpdateBanner`, 사전 `{ version: 문자열, dismissedAt: 날짜 }`). 키가 빠졌거나 타입이 다르거나
  /// 버전을 해석할 수 없으면 nil (숨김 없음).
  func updateBannerDismissal() -> UpdateBannerDismissal?

  /// 잠겼으면 `.locked` 이고 쓰지 않는다.
  func setUpdateBannerDismissal(_ dismissal: UpdateBannerDismissal) throws(PreferencesError)

  /// 서버가 답한 마지막 최신 버전 (키 `LatestKnownUpdateVersion`, `AppVersion.description` 문자열). 문자열이 아니면 nil.
  /// 해석은 부르는 쪽이 한다.
  func latestKnownUpdateVersion() -> String?

  /// nil 이면 키를 지운다. 잠겼으면 쓰지도 지우지도 않는다 (던지지 않는다: 부르는 쪽은 이 실행의 값을 메모리에 들고 있다).
  func setLatestKnownUpdateVersion(_ version: String?)
}
