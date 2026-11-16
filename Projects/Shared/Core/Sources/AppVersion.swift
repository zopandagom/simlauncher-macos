/// 숫자 버전 (버전 파일의 값(= 릴리스 태그)·CFBundleShortVersionString). 비교할 수 있는 형식만 만들어진다.
/// 업데이트 알림이 지금 버전과 GitHub 최신 릴리스의 버전 파일 값(= 릴리스 태그)을 비교하는 데 쓰고,
/// 화면과 저장(`SkippedUpdateVersion` 등)에는 `description` 만 쓴다 (원문 문자열은 쓰지 않는다).
public struct AppVersion: Hashable, Comparable, Sendable, CustomStringConvertible {
  /// 끝의 0 을 뺀 자리 (최소 1개). "1.2.0" → [1, 2], "1.0" → [1], "0" → [0].
  public let components: [Int]

  /// 자리 수 상한. 5자리 이상은 비교 불가다.
  static let maxComponents = 4
  /// 한 자리의 숫자 개수 상한. 10자 이상은 비교 불가다 (Int 범위 안에서 확실히 읽는다).
  static let maxDigits = 9

  /// 규칙: 앞에 `v`·`V` 하나를 허용. 나머지는 1~4 자리를 `.` 로 이은 것, 각 자리는 ASCII 숫자 1~9개(앞자리 0 허용, 값으로 비교).
  /// 공백·부호·접미사(`-beta`, `+3`)·빈 자리(`1..2`, `.1`, `1.`)·5자리 이상·전각 숫자·10자 이상 숫자는 nil (비교 불가).
  public init?(_ text: String) {
    var body = Substring(text)
    if let first = body.first, first == "v" || first == "V" {
      body = body.dropFirst()
    }
    let parts = body.split(separator: ".", omittingEmptySubsequences: false)
    guard (1 ... Self.maxComponents).contains(parts.count) else {
      return nil
    }
    var values: [Int] = []
    values.reserveCapacity(parts.count)
    for part in parts {
      guard
        (1 ... Self.maxDigits).contains(part.utf8.count),
        part.utf8.allSatisfy({ (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains($0) }),
        let value = Int(part)
      else {
        return nil
      }
      values.append(value)
    }
    self.init(normalizing: values)
  }

  private init(normalizing values: [Int]) {
    var trimmed = values
    while trimmed.count > 1, trimmed.last == 0 {
      trimmed.removeLast()
    }
    self.components = trimmed
  }

  /// 3자리 미만이면 0 을 채워 3자리로: [1,2] → "1.2.0", [1] → "1.0.0", [1,2,3,4] → "1.2.3.4". 화면에 보이는 유일한 버전 문자열이자 저장 형식.
  public var description: String {
    var shown = self.components
    while shown.count < 3 {
      shown.append(0)
    }
    return shown.map(String.init).joined(separator: ".")
  }

  /// 자리별 숫자 비교, 짧은 쪽은 0 으로 채운다 (1.2 == 1.2.0 < 1.10).
  public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
    let count = max(lhs.components.count, rhs.components.count)
    for index in 0 ..< count {
      let left = index < lhs.components.count ? lhs.components[index] : 0
      let right = index < rhs.components.count ? rhs.components[index] : 0
      if left != right {
        return left < right
      }
    }
    return false
  }
}
