import Core
import Foundation
import PreferencesInterface

/// 설정 키 이름. 공개 규격(docs/CATALOG.md 9절)에 적은 이름이라 바꾸지 않는다.
enum PreferenceKey {
  static let catalogURLs = "CatalogURLs"
  /// Android SDK 위치 (문자열, 절대 경로 또는 `~/…`). docs/CATALOG.md 9절.
  static let androidSDKPath = "AndroidSDKPath"
  /// 동의한 Android SDK 라이선스 원문의 지문 (문자열 배열). 앱이 기록한다.
  static let acceptedAndroidLicenses = "AcceptedAndroidLicenses"
  /// 저장한 로그 필터 (사전 배열, 형식은 `LogFilterValue`). docs/CATALOG.md 9절.
  static let logFilters = "LogFilters"
}

/// 설정 저장소. Impl 의 판정(잠금·중복·삭제·상한)을 실제 UserDefaults 없이 테스트하려고 둔다.
protocol PreferenceStore: Sendable {
  /// 카탈로그 주소 목록 (`CatalogURLValue.strings(from:)` 로 읽은 값).
  func catalogURLs() -> [String]
  /// 관리자가 이 키를 강제했다.
  func isCatalogURLsForced() -> Bool
  /// 목록을 통째로 쓴다. 빈 목록도 그대로 쓴다.
  func setCatalogURLs(_ urls: [String])

  /// `AndroidSDKPath` 의 값 그대로 (`AndroidPreferenceValue.sdkPath(from:)` 로 읽는다).
  func androidSDKPath() -> AndroidSDKPathSetting.Value
  func isAndroidSDKPathForced() -> Bool
  /// nil 이면 키를 지운다.
  func setAndroidSDKPath(_ path: String?)

  /// `AcceptedAndroidLicenses` 의 문자열 항목 (`AndroidPreferenceValue.strings(from:)` 로 읽는다).
  func acceptedAndroidLicenses() -> [String]
  func isAcceptedAndroidLicensesForced() -> Bool
  /// 배열을 통째로 쓴다.
  func setAcceptedAndroidLicenses(_ fingerprints: [String])

  /// `LogFilters` 항목을 저장 배열과 같은 인덱스로 (읽지 못한 항목 nil). 배열이 아니면 빈 배열.
  func logFilters() -> [SavedLogFilter?]
  func isLogFiltersForced() -> Bool
  /// 지금 값을 다시 읽어 `decide` 에 넘기고, 돌려준 변경을 원본 배열에 적용해 쓴다 (nil 이면 쓰지 않는다).
  /// 읽지 못한 항목과 고치지 않은 항목은 원래 값 그대로 남는다. 적용 뒤(쓰지 않았으면 그대로) 항목을 돌려준다.
  /// 원본 배열(`[Any]`)은 Sendable 이 아니어서 이 메서드 밖으로 내보내지 않는다.
  func updateLogFilters(
    _ decide: ([SavedLogFilter?]) throws(PreferencesError) -> SavedLogFilterList.Change?
  ) throws(PreferencesError) -> [SavedLogFilter?]
}

/// UserDefaults 저장소. `UserDefaults` 는 Sendable 이 아니어서 들고 있지 않고, 호출마다 도메인으로 얻는다.
struct UserDefaultsPreferenceStore: PreferenceStore {
  /// nil 이면 `.standard` (앱 번들 ID 도메인).
  let suiteName: String?

  func catalogURLs() -> [String] {
    CatalogURLValue.strings(from: self.defaults.object(forKey: PreferenceKey.catalogURLs))
  }

  func isCatalogURLsForced() -> Bool {
    self.defaults.objectIsForced(forKey: PreferenceKey.catalogURLs)
  }

  /// 빈 목록도 `set([])` 로 쓴다. `removeObject` 를 쓰면 `/Library/Preferences` 의 전체 사용자 값이 다시 보인다.
  func setCatalogURLs(_ urls: [String]) {
    self.defaults.set(urls, forKey: PreferenceKey.catalogURLs)
  }

  func androidSDKPath() -> AndroidSDKPathSetting.Value {
    AndroidPreferenceValue.sdkPath(from: self.defaults.object(forKey: PreferenceKey.androidSDKPath))
  }

  func isAndroidSDKPathForced() -> Bool {
    self.defaults.objectIsForced(forKey: PreferenceKey.androidSDKPath)
  }

  /// 기본 위치로 되돌릴 때는 키를 지운다 (관리자가 `/Library/Preferences` 에 넣은 값이 있으면 그 값이 다시 보인다).
  func setAndroidSDKPath(_ path: String?) {
    if let path {
      self.defaults.set(path, forKey: PreferenceKey.androidSDKPath)
    } else {
      self.defaults.removeObject(forKey: PreferenceKey.androidSDKPath)
    }
  }

  func acceptedAndroidLicenses() -> [String] {
    AndroidPreferenceValue.strings(from: self.defaults.object(forKey: PreferenceKey.acceptedAndroidLicenses))
  }

  func isAcceptedAndroidLicensesForced() -> Bool {
    self.defaults.objectIsForced(forKey: PreferenceKey.acceptedAndroidLicenses)
  }

  func setAcceptedAndroidLicenses(_ fingerprints: [String]) {
    self.defaults.set(fingerprints, forKey: PreferenceKey.acceptedAndroidLicenses)
  }

  func logFilters() -> [SavedLogFilter?] {
    LogFilterValue.items(from: self.defaults.object(forKey: PreferenceKey.logFilters)).map(LogFilterValue.filter(from:))
  }

  func isLogFiltersForced() -> Bool {
    self.defaults.objectIsForced(forKey: PreferenceKey.logFilters)
  }

  /// 키 값이 배열이 아니었으면 새 배열로 쓴다. 빈 배열도 `set([])` 로 쓴다 (`setCatalogURLs(_:)` 와 같은 이유).
  func updateLogFilters(
    _ decide: ([SavedLogFilter?]) throws(PreferencesError) -> SavedLogFilterList.Change?
  ) throws(PreferencesError) -> [SavedLogFilter?] {
    let defaults = self.defaults
    let raw = LogFilterValue.items(from: defaults.object(forKey: PreferenceKey.logFilters))
    let parsed = raw.map(LogFilterValue.filter(from:))
    guard let change = try decide(parsed) else {
      return parsed
    }
    let written = change.applied(to: raw) { filter -> Any in LogFilterValue.plist(for: filter) }
    defaults.set(written, forKey: PreferenceKey.logFilters)
    return change.applied(to: parsed) { $0 }
  }

  private var defaults: UserDefaults {
    guard let suiteName = self.suiteName, let suite = UserDefaults(suiteName: suiteName) else {
      return .standard
    }
    return suite
  }
}
