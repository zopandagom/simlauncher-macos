/// 풀기 전 목록 검사의 실패.
enum PackageArchiveFailure: Error, Equatable {
  /// 읽지 못함 (항목 없음·맨 위 폴더 없음·트리 읽기 실패).
  case unreadable
  /// 모양이 틀림 (경로 탈출·맨 위 항목 여럿·맨 위가 파일·링크).
  case unsafe
}

/// 풀기 전 목록 검사. 패키지 zip 은 맨 위 폴더 하나(`platform-tools/`·`emulator/`·`arm64-v8a/`)여야 한다.
/// 판정은 푼 뒤 `PackageTreeCheck` 가 다시 하고, 여기서는 쓰기 전에 빨리 거절한다. unzip 의 링크 처리를 실측하지 않았으므로
/// 링크를 만든 뒤 그 아래에 쓰는 zip 은 여기서 막는다 (푼 뒤에는 이미 바깥에 쓴 뒤다).
enum PackageZipListingCheck {
  /// 첫 실패에서 멈춘다:
  /// 1. 항목이 없다 → `.unreadable`.
  /// 2. 어떤 항목이 `/` 로 시작하거나 `/` 로 나눈 구성 요소에 `..` 가 있거나, `.`·빈 구성 요소만 있다 → `.unsafe`.
  /// 3. 맨 위 이름(첫 구성 요소, 대소문자 무시. `__MACOSX` 도 센다)이 둘 이상 → `.unsafe`.
  /// 4. 맨 위 이름 자체가 링크 항목이다 → `.unsafe`.
  /// 5. 맨 위가 폴더가 아니다 (구성 요소 2개 이상인 항목도 그 이름의 폴더 항목도 없다) → `.unsafe`.
  /// 6. 링크 항목의 경로가 다른 항목 경로의 앞부분이다 → `.unsafe`.
  /// 폴더 항목(`d`) 없이 `platform-tools/adb` 만 있는 zip 은 통과한다.
  static func check(_ listing: PackageZipListing) throws(PackageArchiveFailure) {
    guard !listing.entries.isEmpty else {
      throw .unreadable
    }
    let paths = try listing.entries.map { entry throws(PackageArchiveFailure) in
      try EntryPath(components: self.components(of: entry.name), kind: entry.kind)
    }
    let tops = Set(paths.map { $0.components[0].lowercased() })
    guard tops.count == 1 else {
      throw .unsafe
    }
    guard !paths.contains(where: { $0.components.count == 1 && $0.kind == .symlink }) else {
      throw .unsafe
    }
    guard paths.contains(where: { $0.components.count >= 2 || $0.kind == .directory }) else {
      throw .unsafe
    }
    guard !self.linkIsAncestor(in: paths) else {
      throw .unsafe
    }
  }

  private struct EntryPath {
    let components: [String]
    let kind: PackageZipListing.Kind
  }

  /// `.`·빈 구성 요소를 뺀 경로 구성 요소. `/` 로 시작하거나 `..` 가 있거나 남는 구성 요소가 없으면 `.unsafe` (`check` 의 2).
  private static func components(of name: String) throws(PackageArchiveFailure) -> [String] {
    guard !name.hasPrefix("/") else {
      throw .unsafe
    }
    let raw = name.split(separator: "/", omittingEmptySubsequences: false)
    guard !raw.contains("..") else {
      throw .unsafe
    }
    let components = raw.filter { !$0.isEmpty && $0 != "." }.map(String.init)
    guard !components.isEmpty else {
      throw .unsafe
    }
    return components
  }

  /// 링크 항목의 경로가 다른 항목 경로의 앞부분인지 (대소문자 무시, `check` 의 6).
  private static func linkIsAncestor(in paths: [EntryPath]) -> Bool {
    let links = paths.filter { $0.kind == .symlink }.map { $0.components.map { $0.lowercased() } }
    for link in links {
      for path in paths where path.components.count > link.count {
        if Array(path.components.prefix(link.count).map { $0.lowercased() }) == link {
          return true
        }
      }
    }
    return false
  }
}
