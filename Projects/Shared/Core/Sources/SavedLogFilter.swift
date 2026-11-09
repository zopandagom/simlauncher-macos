import Foundation

/// 이름 붙여 저장한 로그 필터 (모든 기기·플랫폼 공용). 만들 때 규칙을 검사해 값이 있으면 규칙을 지킨다.
/// 편집용 필터(조건 id 포함)는 DeviceLog Feature 의 `LogFilter` 이고, 저장·불러오기 때 이 값으로 바꾼다.
public struct SavedLogFilter: Hashable, Sendable {
  /// 조건 종류. `rawValue` 가 저장 철자다 (docs/CATALOG.md 9절, 이 철자 그대로).
  public enum Kind: String, Hashable, Sendable, CaseIterable {
    case contains
    case prefix
    case regex
  }

  /// 조건 하나. 글자는 그대로 저장한다 (앞뒤 공백도 거르기에 쓰이므로 자르지 않는다).
  public struct Condition: Hashable, Sendable {
    public let kind: Kind
    public let text: String
    public let isExcluded: Bool

    public init(kind: Kind, text: String, isExcluded: Bool) {
      self.kind = kind
      self.text = text
      self.isExcluded = isExcluded
    }
  }

  /// 이름 최대 글자 수 (앞뒤 공백을 자른 뒤 `Character` 수).
  public static let maxNameLength = 40
  /// 필터 하나의 최대 조건 수.
  public static let maxConditions = 20
  /// 조건 글자 최대 글자 수 (`Character` 수).
  public static let maxTextLength = 1000
  /// 보이는 목록(`SavedLogFilterList.visible`) 상한. 새 이름 저장에만 건다.
  public static let maxCount = 50

  /// 앞뒤 공백·개행을 자른 값.
  public let name: String
  public let conditions: [Condition]
  public let isCaseSensitive: Bool

  /// 이름을 잘라 규칙에 맞으면 값, 아니면 nil (이유는 `problem(name:conditions:)`).
  public init?(name: String, conditions: [Condition], isCaseSensitive: Bool) {
    guard Self.problem(name: name, conditions: conditions) == nil else {
      return nil
    }
    self.name = Self.normalizedName(name)
    self.conditions = conditions
    self.isCaseSensitive = isCaseSensitive
  }

  /// 저장하는 이름: 앞뒤 공백·개행을 자른다.
  public static func normalizedName(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// 규칙 문제 하나. 순서: emptyName → nameTooLong → noConditions → tooManyConditions → emptyText → textTooLong. 없으면 nil.
  public static func problem(name: String, conditions: [Condition]) -> SavedLogFilterProblem? {
    self.nameProblem(name) ?? self.conditionsProblem(conditions)
  }

  /// 이름 문제 (자른 뒤): 비었으면 emptyName, 40자를 넘으면 nameTooLong.
  public static func nameProblem(_ raw: String) -> SavedLogFilterProblem? {
    let name = self.normalizedName(raw)
    if name.isEmpty {
      return .emptyName
    }
    if name.count > self.maxNameLength {
      return .nameTooLong
    }
    return nil
  }

  /// 조건 문제. 순서: noConditions → tooManyConditions → emptyText → textTooLong (어느 조건이든 먼저 걸리는 규칙).
  public static func conditionsProblem(_ conditions: [Condition]) -> SavedLogFilterProblem? {
    if conditions.isEmpty {
      return .noConditions
    }
    if conditions.count > self.maxConditions {
      return .tooManyConditions
    }
    if conditions.contains(where: \.text.isEmpty) {
      return .emptyText
    }
    if conditions.contains(where: { $0.text.count > self.maxTextLength }) {
      return .textTooLong
    }
    return nil
  }

  /// 자른 두 이름이 대소문자 무시로 같다.
  public static func isSameName(_ lhs: String, _ rhs: String) -> Bool {
    self.normalizedName(lhs).compare(self.normalizedName(rhs), options: .caseInsensitive) == .orderedSame
  }
}

/// 저장된 로그 필터 규칙 문제. 화면 문구는 Feature 가 정한다.
public enum SavedLogFilterProblem: Hashable, Sendable {
  /// 이름이 비었거나 공백뿐이다.
  case emptyName
  /// 이름이 40자를 넘는다.
  case nameTooLong
  /// 조건이 없다.
  case noConditions
  /// 조건이 20개를 넘는다.
  case tooManyConditions
  /// 글자가 빈 조건이 있다.
  case emptyText
  /// 글자가 1000자를 넘는 조건이 있다.
  case textTooLong
}
