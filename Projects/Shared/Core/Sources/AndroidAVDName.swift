/// AVD 이름 규칙. emulator 는 공백·한글이 든 이름의 AVD 를 켜면 SIGSEGV 로 죽고(실측), `-avd` 다음 인자가 `-` 로 시작하면
/// 옵션처럼 읽힐 수 있다 → 켜기·만들기·초기화는 이 검사를 통과한 이름만 쓴다. 사용자는 표시 이름을 입력하고 앱이 이 이름을 만든다.
public enum AndroidAVDName {
  public static let maxLength = 100
  /// `make` 가 만드는 이름 앞부분의 최대 길이 (뒤에 `_99` 가 붙어도 `maxLength` 안).
  public static let generatedLength = 60
  /// 표시 이름에서 쓸 글자가 하나도 남지 않을 때의 이름.
  public static let fallback = "Android_Device"

  /// `^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$`.
  public static func isValid(_ name: String) -> Bool {
    let scalars = Array(name.unicodeScalars)
    guard let first = scalars.first, scalars.count <= self.maxLength, self.isAlphanumeric(first) else {
      return false
    }
    return scalars.allSatisfy(self.isAllowed)
  }

  /// 표시 이름에서 AVD 이름을 만든다: ASCII 영문·숫자·`.`·`_`·`-` 는 두고 나머지 연속 구간은 `_` 하나(바로 앞이 `_` 면 더하지 않는다),
  /// 앞의 `._-` 를 빼고 `generatedLength` 로 자른다. 비면 `fallback`. `existing` 과 대소문자 무시로 겹치면 `_2`…`_99` 를 붙이고, 모두 겹치면 nil.
  public static func make(from displayName: String, existing: Set<String>) -> String? {
    var scalars: [Unicode.Scalar] = []
    for scalar in displayName.unicodeScalars {
      if self.isAllowed(scalar) {
        scalars.append(scalar)
      } else if scalars.last != "_" {
        scalars.append("_")
      }
    }
    let trimmed = scalars.drop { !self.isAlphanumeric($0) }.prefix(self.generatedLength)
    var base = String(String.UnicodeScalarView(trimmed))
    if base.isEmpty {
      base = self.fallback
    }
    let taken = Set(existing.map { $0.lowercased() })
    if !taken.contains(base.lowercased()) {
      return base
    }
    for number in 2 ... 99 {
      let candidate = "\(base)_\(number)"
      if !taken.contains(candidate.lowercased()) {
        return candidate
      }
    }
    return nil
  }

  private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar {
    case "A" ... "Z", "a" ... "z", "0" ... "9": true
    default: false
    }
  }

  private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
    self.isAlphanumeric(scalar) || scalar == "." || scalar == "_" || scalar == "-"
  }
}
