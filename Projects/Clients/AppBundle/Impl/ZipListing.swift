/// `zipinfo -s -T` 출력. 중앙 디렉터리만 읽은 값이라 이름·크기를 믿지 않고, 풀기 전에 빨리 거절하는 데만 쓴다.
/// 비ASCII 바이트는 `?`, 제어 문자는 `^I`·`^J` 처럼 바뀌어 나온다 (빈 환경, 실행해 본 값).
struct ZipListing: Equatable {
  enum Kind: Equatable {
    case file, directory, symlink, other
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

  /// 항목 크기 합. 넘치면 `Int64.max` 에서 멈춘다.
  var declaredTotalBytes: Int64 {
    var total: Int64 = 0
    for entry in self.entries {
      let (sum, overflow) = total.addingReportingOverflow(entry.size)
      if overflow {
        return .max
      }
      total = sum
    }
    return total
  }

  /// 1줄 `Archive:`, 2줄 `Zip file size: <n> bytes, number of entries: <m>`, 그다음 m 줄이 항목이다.
  /// 항목이 0 개면 빈 zip 의 `Empty zipfile.` 줄은 보지 않는다. 요약 줄은 검사하지 않는다 (단수 `1 file,` 도 있다).
  /// 헤더 형식이 다르거나, 줄이 모자라거나, 항목 줄을 읽지 못하면 nil (zipinfo 경고 줄이 끼어도 nil 이 된다).
  static func parse(_ stdout: String) -> ZipListing? {
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
    return ZipListing(declaredCount: count, entries: entries)
  }

  /// 공백을 건너뛰며 7개 열(권한·버전·OS·풀린 크기·플래그·방식·시각)을 읽고, 공백 하나 다음의 나머지 전체가 이름이다
  /// (이름 앞뒤·안의 공백을 보존한다).
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
    let kind: Kind = switch columns[0].first {
    case "d": .directory
    case _ where name.hasSuffix("/"): .directory
    case "l": .symlink
    case "-": .file
    default: .other
    }
    return Entry(name: name, size: size, kind: kind)
  }
}
