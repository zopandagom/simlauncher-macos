/// 시뮬레이터 기기에 사용자가 설치한 앱 하나 (`simctl listapps` 의 `ApplicationType = User`).
public struct InstalledApp: Hashable, Sendable, Identifiable {
  public let bundleID: AppBundleID
  /// 화면 이름: CFBundleDisplayName → CFBundleName → 번들 ID 순으로 처음 있는(빈 문자열 아님) 값. 앱이 정한 글자라 그대로 보인다.
  public let displayName: String
  /// CFBundleShortVersionString. 없으면 nil.
  public let version: String?
  /// CFBundleVersion. 없으면 nil.
  public let build: String?

  public var id: AppBundleID {
    self.bundleID
  }

  public init(bundleID: AppBundleID, displayName: String, version: String?, build: String?) {
    self.bundleID = bundleID
    self.displayName = displayName
    self.version = version
    self.build = build
  }
}
