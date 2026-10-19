import AppBundleInterface

/// .app 이름 판정. 풀기 전 목록 검사와 푼 뒤 트리 검사가 함께 쓴다.
enum ZipNames {
  /// 소문자로 `.app` 으로 끝나고 그 앞에 한 글자 이상 있다. 정확히 `.app` 인 이름은 아니다
  /// (`URL(filePath: "/x/.app").pathExtension` 이 빈 문자열인 것과 맞춘다).
  static func isAppName(_ name: String) -> Bool {
    let lowercased = name.lowercased()
    return lowercased.hasSuffix(".app") && lowercased.count > ".app".count
  }

  /// Finder 압축이 넣는 메타데이터 (`__MACOSX`·`._*`). 맨 위 판정에서 무시한다.
  static func isMetadata(_ name: String) -> Bool {
    name == "__MACOSX" || name.hasPrefix("._")
  }
}

/// 풀기 전 목록 검사. 모양이 틀린 zip 을 쓰기 전에 빨리 거절하는 보조 단계이고, 판정은 푼 뒤 `ExtractedTreeCheck` 가 한다
/// (ditto 는 중앙 디렉터리에 없는 항목도 풀고, 이름은 zipinfo 출력에서 깨진다).
enum ZipListingCheck {
  /// 첫 실패에서 멈춘다: 모든 항목의 경로 → 맨 위 .app 개수. 백슬래시는 구분자로 보지 않는다 (ditto 와 같다).
  static func check(_ listing: ZipListing) throws(AppBundleError) {
    for entry in listing.entries where self.escapes(entry.name) {
      throw .zipUnsafeEntry
    }
    var apps: Set<String> = []
    for entry in listing.entries {
      let components = entry.name.split(separator: "/").filter { $0 != "." }
      guard let first = components.first.map(String.init), !ZipNames.isMetadata(first), ZipNames.isAppName(first) else {
        // README·`X.app.dSYM` 같은 다른 맨 위 항목은 세지 않는다 (사용자 결정).
        continue
      }
      if components.count >= 2 || entry.kind == .directory {
        // 기본 APFS 는 대소문자를 구분하지 않아 ditto 가 `Sample.app/`·`SAMPLE.APP/x` 를 한 폴더로 합친다.
        apps.insert(first.lowercased())
      } else if entry.kind == .symlink {
        throw .zipUnsafeEntry
      }
    }
    if apps.isEmpty {
      throw .zipWithoutApp
    }
    if apps.count > 1 {
      throw .zipWithMultipleApps
    }
  }

  /// `/` 로 시작하거나 `/` 로 나눈 구성 요소 중 `..` 가 있다.
  private static func escapes(_ name: String) -> Bool {
    name.hasPrefix("/") || name.split(separator: "/", omittingEmptySubsequences: false).contains("..")
  }
}
