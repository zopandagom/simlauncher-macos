import AndroidPackageInterface

/// `zipinfo -s -T` 출력 (AndroidSDK Impl 의 `PackageZipListing` 을 복제했다. Impl 끼리 import 할 수 없다).
/// 다른 점은 종류 판정이다: 링크(`l`)·폴더(`d` 또는 이름 끝 `/`)가 아니면 모두 파일로 본다 (권한 열이 `-`·`?` 등).
/// apk 는 Mac 에 풀지 않으므로 링크만 거절할 이유가 남는다 (Android 가 쓰지 않는 항목이라 실수·손상 신호).
/// 중앙 디렉터리만 읽은 값이라 이름·크기를 믿지 않고, 기기에 보내기 전에 빨리 거절하는 데만 쓴다.
struct APKZipListing: Equatable {
  enum Kind: Equatable {
    case file, directory, symlink
  }

  struct Entry: Equatable {
    let name: String
    /// 중앙 디렉터리가 선언한 풀린 크기 (속일 수 있다).
    let size: Int64
    let kind: Kind
  }

  /// 헤더의 `number of entries`.
  let declaredCount: Int
  let entries: [Entry]

  /// 1줄 `Archive:`, 2줄 `Zip file size: <n> bytes, number of entries: <m>`, 그다음 m 줄이 항목이다. 요약 줄은 보지 않는다.
  /// 헤더 형식이 다르거나, 줄이 모자라거나, 항목 줄을 읽지 못하면 nil (경고 줄이 끼어도 nil).
  static func parse(_ stdout: String) -> APKZipListing? {
    let lines = stdout.split(separator: "\n", omittingEmptySubsequences: false)
    guard
      lines.count >= 2,
      lines[0].hasPrefix("Archive:"),
      let header = lines[1].wholeMatch(of: /Zip file size: \d+ bytes, number of entries: (\d+)/),
      let count = Int(header.output.1)
    else {
      return nil
    }
    guard lines.count >= 2 + count else {
      return nil
    }
    var entries: [Entry] = []
    entries.reserveCapacity(count)
    for line in lines[2 ..< 2 + count] {
      guard let entry = Self.entry(line) else {
        return nil
      }
      entries.append(entry)
    }
    return APKZipListing(declaredCount: count, entries: entries)
  }

  /// 공백을 건너뛰며 7개 열(권한·버전·OS·풀린 크기·플래그·방식·시각)을 읽고, 공백 하나 다음의 나머지 전체가 이름이다.
  private static func entry(_ line: Substring) -> Entry? {
    var rest = line
    var columns: [Substring] = []
    for _ in 0 ..< 7 {
      rest = rest.drop(while: { $0 == " " })
      let column = rest.prefix(while: { $0 != " " })
      guard !column.isEmpty else {
        return nil
      }
      columns.append(column)
      rest = rest.dropFirst(column.count)
    }
    guard rest.first == " ", let size = Int64(columns[3]), size >= 0 else {
      return nil
    }
    let name = String(rest.dropFirst())
    guard !name.isEmpty else {
      return nil
    }
    // 링크(`l`)는 이름 끝 `/` 보다 먼저 본다: `/` 로 끝나는 링크도 링크로 거절한다.
    // 직접 만든 zip(Python)은 형식 비트가 없어 권한 열이 `?rw-------` 다 (실측) → 파일.
    let kind: Kind = switch columns[0].first {
    case "l": .symlink
    case "d": .directory
    case _ where name.hasSuffix("/"): .directory
    default: .file
    }
    return Entry(name: name, size: size, kind: kind)
  }
}

/// 목록 검사를 통과한 apk 의 항목 요약.
struct APKEntries: Equatable {
  /// 이름이 `lib/<abi>/<비지 않은 나머지>` 인 파일 항목의 `<abi>`.
  let nativeABIs: Set<String>
  /// `META-INF/<이름>.RSA`·`.DSA`·`.EC` 인 파일 항목이 있다 (하위 폴더는 아님, 대소문자 무시).
  let hasV1Signature: Bool
}

extension APKZipListing {
  /// 첫 실패에서 멈춘다:
  /// 1. 링크 항목이 있다 → `.unsafeEntry`.
  /// 2. 이름이 `/` 로 시작하거나 `/` 로 나눈 구성 요소에 `..` 가 있다 → `.unsafeEntry`.
  /// 3. 이름이 정확히 `AndroidManifest.xml` 인 파일이 0개면 `base/manifest/AndroidManifest.xml` 이 있을 때 `.appBundle`,
  ///    없으면 `.unreadable`. 2개 이상이거나 선언 크기가 상한을 넘으면 `.unreadable`.
  func check() -> Result<APKEntries, AndroidPackageError> {
    for entry in self.entries {
      if entry.kind == .symlink || entry.name.hasPrefix("/") {
        return .failure(.unsafeEntry)
      }
      if entry.name.split(separator: "/", omittingEmptySubsequences: false).contains("..") {
        return .failure(.unsafeEntry)
      }
    }
    let manifests = self.entries.filter { $0.kind == .file && $0.name == APKCommand.manifestEntry }
    switch manifests.count {
    case 0:
      let isBundle = self.entries.contains { $0.kind == .file && $0.name == Self.bundleManifest }
      return .failure(isBundle ? .appBundle : .unreadable)
    case 1 where manifests[0].size <= Int64(AXMLManifestReader.sizeLimit):
      break
    default:
      return .failure(.unreadable)
    }
    let files = self.entries.filter { $0.kind == .file }
    return .success(APKEntries(
      nativeABIs: Set(files.compactMap { Self.nativeABI(of: $0.name) }),
      hasV1Signature: files.contains { Self.isV1SignatureFile($0.name) }
    ))
  }

  /// App Bundle(.aab) 의 base 모듈 manifest 위치 (bundletool 형식).
  private static let bundleManifest = "base/manifest/AndroidManifest.xml"

  private static func nativeABI(of name: String) -> String? {
    let parts = name.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0] == "lib", !parts[1].isEmpty, !parts[2].isEmpty else {
      return nil
    }
    return String(parts[1])
  }

  private static func isV1SignatureFile(_ name: String) -> Bool {
    let parts = name.lowercased().split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2, parts[0] == "meta-inf" else {
      return false
    }
    let file = parts[1]
    return [".rsa", ".dsa", ".ec"].contains { file.hasSuffix($0) && file.count > $0.count }
  }
}
