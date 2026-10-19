import Foundation

/// 기기 이름 검사에서 걸린 문제.
public enum DeviceNameProblem: Hashable, Sendable {
  /// 앞뒤 공백·개행을 빼면 비었다.
  case empty
  /// `DeviceName.maxLength`(Character 수)를 넘는다.
  case tooLong
  /// 개행·탭 같은 제어 문자(일반 범주 Cc)가 들어 있다.
  /// `CharacterSet.controlCharacters` 는 Cf(ZWJ U+200D 등)까지 막아 ZWJ 이모지 이름을 거부하므로 쓰지 않는다.
  case containsControlCharacter
}

/// 새 기기 이름 규칙. simctl 은 빈 이름·제어 문자·아주 긴 이름도 그대로 저장하므로 여기서 막는다.
public enum DeviceName {
  public static let maxLength = 100

  /// 앞뒤 공백·개행을 뺀 이름. simctl 에는 이 값을 넘긴다.
  public static func normalized(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// `normalized` 기준의 문제. 없으면 nil. 순서: empty → containsControlCharacter → tooLong.
  /// `-` 로 시작하는 이름은 허용한다 (Impl 이 `--` 뒤에 넘긴다). 같은 이름도 허용한다 (simctl 이 허용).
  public static func problem(in raw: String) -> DeviceNameProblem? {
    let name = Self.normalized(raw)
    if name.isEmpty {
      return .empty
    }
    if name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
      return .containsControlCharacter
    }
    if name.count > Self.maxLength {
      return .tooLong
    }
    return nil
  }
}
