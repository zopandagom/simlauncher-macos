/// Android SDK 패키지 revision (저장소 XML 의 `<revision>`, `source.properties` 의 `Pkg.Revision`).
/// 비교는 major → minor → micro 순서이고, 숫자가 같으면 preview 가 없는 쪽(정식)이 높다. 빠진 minor·micro 는 0 이다.
public struct AndroidRevision: Hashable, Sendable, Comparable, CustomStringConvertible {
  public let major: Int
  public let minor: Int
  public let micro: Int
  /// 미리보기 번호 (`rc1` 등). 정식이면 nil.
  public let preview: Int?

  public init(major: Int, minor: Int = 0, micro: Int = 0, preview: Int? = nil) {
    self.major = major
    self.minor = minor
    self.micro = micro
    self.preview = preview
  }

  /// `Pkg.Revision` 문자열: 점으로 나눈 0 이상의 10진 정수 1~3 개 (`37.0.1`·`7`·`37.2.12`). 앞뒤 공백은 뺀다.
  /// 그 밖(빈 문자열·숫자 아닌 글자·4 개 이상·빈 구성 요소·`37.0.0 rc1` 같은 미리보기 표기)은 nil.
  public init?(_ string: String) {
    let parts = string.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
    guard (1 ... 3).contains(parts.count) else {
      return nil
    }
    var numbers: [Int] = []
    for part in parts {
      guard !part.isEmpty, part.allSatisfy(\.isASCIIDigit), let number = Int(part) else {
        return nil
      }
      numbers.append(number)
    }
    self.init(
      major: numbers[0],
      minor: numbers.count > 1 ? numbers[1] : 0,
      micro: numbers.count > 2 ? numbers[2] : 0
    )
  }

  /// `37.0.1`, 미리보기면 `37.0.0 rc1`.
  public var description: String {
    let base = "\(self.major).\(self.minor).\(self.micro)"
    guard let preview = self.preview else {
      return base
    }
    return "\(base) rc\(preview)"
  }

  public static func < (lhs: AndroidRevision, rhs: AndroidRevision) -> Bool {
    if (lhs.major, lhs.minor, lhs.micro) != (rhs.major, rhs.minor, rhs.micro) {
      return (lhs.major, lhs.minor, lhs.micro) < (rhs.major, rhs.minor, rhs.micro)
    }
    switch (lhs.preview, rhs.preview) {
    case let (left?, right?): return left < right
    case (.some, nil): return true
    default: return false
    }
  }
}

extension Character {
  /// `0`~`9` (전각·다른 문자 체계 숫자는 아니다).
  var isASCIIDigit: Bool {
    self.isASCII && self.isNumber
  }
}
