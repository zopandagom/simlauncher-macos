/// Android SDK 패키지 경로 (`platform-tools`, `system-images;android-37.0;google_apis;arm64-v8a`).
/// `;` 로 나눈 구성 요소가 SDK 루트 아래 최종 경로가 된다. 그래서 경로 밖으로 나가거나 이름이 아닌 구성 요소는 받지 않는다.
public struct AndroidPackagePath: Hashable, Sendable {
  /// 저장소 XML 의 `path` 값 그대로.
  public let raw: String
  public let components: [String]

  /// 모든 구성 요소가 비어 있지 않고, `.`·`..` 가 아니고, `/`·NUL 을 담지 않을 때만 만들어진다.
  public init?(_ raw: String) {
    let components = raw.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
    for component in components {
      guard
        !component.isEmpty,
        component != ".",
        component != "..",
        !component.contains("/"),
        !component.contains("\0")
      else {
        return nil
      }
    }
    self.raw = raw
    self.components = components
  }
}
