import Core
import Foundation

/// 설정 키 이름. 공개 규격(docs/CATALOG.md 9절)에 적은 이름이라 바꾸지 않는다.
enum PreferenceKey {
  static let catalogURLs = "CatalogURLs"
  /// Android SDK 위치 (문자열, 절대 경로 또는 `~/…`). docs/CATALOG.md 9절.
  static let androidSDKPath = "AndroidSDKPath"
  /// 동의한 Android SDK 라이선스 원문의 지문 (문자열 배열). 앱이 기록한다.
  static let acceptedAndroidLicenses = "AcceptedAndroidLicenses"
}

/// 설정 저장소. Impl 의 판정(잠금·중복·삭제)을 실제 UserDefaults 없이 테스트하려고 둔다.
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

  private var defaults: UserDefaults {
    guard let suiteName = self.suiteName, let suite = UserDefaults(suiteName: suiteName) else {
      return .standard
    }
    return suite
  }
}
