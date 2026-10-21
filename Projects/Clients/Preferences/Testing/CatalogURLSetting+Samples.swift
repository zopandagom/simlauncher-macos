import PreferencesInterface

public extension CatalogURLSetting {
  /// 쓸 수 있는 주소 2개.
  static let sample = CatalogURLSetting(
    urls: [
      "https://builds.example.com/ios/catalog.json",
      "https://cdn.example.org/team/catalog.json",
    ],
    isLocked: false
  )

  /// 쓸 수 있는 주소, http 주소, 앞 항목과 같은 카탈로그, 빈 문자열, 사용자 이름이 든 주소를 섞은 목록
  /// (관리자가 `defaults write` 로 미리 넣은 값을 흉내 낸다).
  static let withProblems = CatalogURLSetting(
    urls: [
      "https://builds.example.com/ios/catalog.json",
      "http://builds.example.com/ios/catalog.json",
      "HTTPS://BUILDS.EXAMPLE.COM:443/ios/catalog.json",
      "",
      "https://user:pw@builds.example.com/ios/catalog.json",
    ],
    isLocked: false
  )

  /// 관리자가 강제한 목록.
  static let locked = CatalogURLSetting(
    urls: ["https://builds.example.com/ios/catalog.json"],
    isLocked: true
  )
}
