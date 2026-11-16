import Core
import Foundation

/// 업데이트 알림 설정·기록 값 해석 (docs/CATALOG.md 9절). 관리자가 `defaults write` 로 넣은 값은 형식이 다를 수 있다.
/// `AutomaticUpdateCheck` 의 문자열·`as? Bool` 처리는 `LogFilterValue.bool(from:)` 와 같고, 다른 점은 둘이다:
/// 키 없음은 켬(기본값)이고, 읽을 수 없는 값은 끔이다 (무언가 넣었는데 해석할 수 없으면 네트워크를 쓰지 않는 쪽이 안전하다).
enum UpdatePreferenceValue {
  /// `DismissedUpdateBanner` 사전의 버전 키 (`AppVersion.description`).
  static let versionKey = "version"
  /// `DismissedUpdateBanner` 사전의 시각 키 (날짜).
  static let dismissedAtKey = "dismissedAt"

  /// 키 없음(nil) → 켬. `as? Bool` 이 값을 주면(CFBoolean, 숫자 0·1) 그 값. 문자열이면 대소문자 무시 `yes`·`true`·`1` → 켬,
  /// `no`·`false`·`0` → 끔. 그 밖(숫자 2, 다른 문자열, 빈 문자열, 배열·사전·날짜) → 끔.
  static func automaticUpdateCheck(from value: Any?) -> Bool {
    guard let value else {
      return true
    }
    if let string = value as? String {
      switch string.lowercased() {
      case "yes", "true", "1":
        return true
      default:
        return false
      }
    }
    return value as? Bool ?? false
  }

  /// 문자열이면 그대로, 그 밖 → nil.
  static func string(from value: Any?) -> String? {
    value as? String
  }

  /// 날짜면 그 값, 그 밖 → nil.
  static func date(from value: Any?) -> Date? {
    value as? Date
  }

  /// 사전이고 `version` 이 `AppVersion` 으로 해석되는 문자열이고 `dismissedAt` 이 날짜면 숨김, 그 밖(키 빠짐·타입 다름·해석 불가) → nil.
  static func bannerDismissal(from value: Any?) -> UpdateBannerDismissal? {
    guard
      let dictionary = value as? [String: Any],
      let rawVersion = dictionary[self.versionKey] as? String,
      let version = AppVersion(rawVersion),
      let dismissedAt = dictionary[self.dismissedAtKey] as? Date
    else {
      return nil
    }
    return UpdateBannerDismissal(version: version, dismissedAt: dismissedAt)
  }

  /// 쓰기 형식: `{ version: AppVersion.description, dismissedAt: 날짜 }`.
  static func plist(for dismissal: UpdateBannerDismissal) -> [String: Any] {
    [
      self.versionKey: dismissal.version.description,
      self.dismissedAtKey: dismissal.dismissedAt,
    ]
  }
}
