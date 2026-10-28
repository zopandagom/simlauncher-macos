import Core
import Foundation

/// 저장된 Android 설정 값 해석. 관리자가 `defaults write` 로 넣은 값은 형식이 다를 수 있다.
enum AndroidPreferenceValue {
  /// nil → `.absent`, 문자열 → `.path` (공백·빈 문자열 그대로), 그 밖(숫자·배열·Data·사전) → `.malformed`.
  static func sdkPath(from value: Any?) -> AndroidSDKPathSetting.Value {
    guard let value else {
      return .absent
    }
    guard let string = value as? String else {
      return .malformed
    }
    return .path(string)
  }

  /// 배열이면 문자열 항목만 순서대로, 그 밖(nil·문자열 하나·숫자·사전)은 빈 목록.
  static func strings(from value: Any?) -> [String] {
    guard let array = value as? [Any] else {
      return []
    }
    return array.compactMap { $0 as? String }
  }
}
