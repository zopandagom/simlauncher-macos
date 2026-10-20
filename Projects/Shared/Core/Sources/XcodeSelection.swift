/// 쓸 Xcode 를 고르는 규칙. 환경 확인과 개발자 디렉터리 provider 가 함께 쓴다.
public enum XcodeSelection {
  /// App Store 로 설치한 Xcode 의 번들 이름.
  static let defaultBundleName = "Xcode.app"

  /// `selected`(xcode-select 가 가리키는 Xcode 번들로 확인된 값)가 있으면 그것.
  /// 없으면 `installed` 중 버전이 가장 높은 것. 같은 버전이면 번들 이름이 정확히 "Xcode.app" 인 것 먼저,
  /// 그다음 bundleURL 경로 문자열 오름차순. 비었으면 nil.
  /// 베타(Xcode-beta.app)도 버전이 높으면 고른다.
  public static func choose(selected: XcodeInstallation?, installed: [XcodeInstallation]) -> XcodeInstallation? {
    if let selected {
      return selected
    }
    return installed.min { lhs, rhs in
      if lhs.version != rhs.version {
        return lhs.version > rhs.version
      }
      let lhsIsDefault = lhs.bundleURL.lastPathComponent == Self.defaultBundleName
      let rhsIsDefault = rhs.bundleURL.lastPathComponent == Self.defaultBundleName
      if lhsIsDefault != rhsIsDefault {
        return lhsIsDefault
      }
      return lhs.bundleURL.path(percentEncoded: false) < rhs.bundleURL.path(percentEncoded: false)
    }
  }
}
