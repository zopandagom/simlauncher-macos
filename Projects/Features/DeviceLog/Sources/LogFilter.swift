import Core
import Foundation

/// 로그 창 하나의 필터 입력: 조건 목록과 대소문자 구분. 순수 값이고, 맞춤은 `compiled()` 가 만든 `CompiledLogFilter` 가 한다.
/// 규칙: 제외가 아닌 조건(포함 조건)이 하나라도 맞으면 보이고(없으면 모든 줄), 제외 조건이 하나라도 맞으면 숨긴다. 빈 조건은 뺀다.
public struct LogFilter: Hashable, Sendable {
  public enum Kind: Hashable, Sendable, CaseIterable {
    /// 줄 어디든 글자 그대로 들어 있다.
    case contains
    /// 머리말(`LogLineHeader`) 뒤 메시지가 글자 그대로 이것으로 시작한다.
    case prefix
    /// 줄 전체에서 정규식(`NSRegularExpression`)이 맞는다.
    case regex
  }

  public struct Condition: Identifiable, Hashable, Sendable {
    public let id: Int
    public fileprivate(set) var kind: Kind
    public fileprivate(set) var text: String
    public fileprivate(set) var isExcluded: Bool
  }

  /// 늘 하나 이상이다 (마지막 조건을 지우면 빈 조건 하나가 남는다).
  public private(set) var conditions: [Condition]
  public private(set) var isCaseSensitive = false
  private var nextID: Int

  public init() {
    self.conditions = [Condition(id: 0, kind: .contains, text: "", isExcluded: false)]
    self.nextID = 1
  }

  mutating func addCondition() {
    self.conditions.append(Condition(id: self.nextID, kind: .contains, text: "", isExcluded: false))
    self.nextID += 1
  }

  /// 마지막 하나를 지우면 빈 조건으로 바꾼다 (입력란이 늘 하나 있게).
  mutating func removeCondition(_ id: Int) {
    self.conditions.removeAll { $0.id == id }
    if self.conditions.isEmpty {
      self.addCondition()
    }
  }

  mutating func setText(_ text: String, of id: Int) {
    self.update(id) { $0.text = text }
  }

  mutating func setKind(_ kind: Kind, of id: Int) {
    self.update(id) { $0.kind = kind }
  }

  mutating func setExcluded(_ isExcluded: Bool, of id: Int) {
    self.update(id) { $0.isExcluded = isExcluded }
  }

  mutating func setCaseSensitive(_ isCaseSensitive: Bool) {
    self.isCaseSensitive = isCaseSensitive
  }

  /// 저장된 필터(`SavedLogFilter`)로 조건과 대소문자 구분을 통째로 바꾼다.
  /// 조건 id 는 지금 `nextID` 부터 이어 매긴다 (앞 조건 id 를 다시 쓰지 않아 입력란 정체가 섞이지 않는다).
  mutating func load(_ saved: SavedLogFilter) {
    var conditions: [Condition] = []
    for condition in saved.conditions {
      conditions.append(Condition(
        id: self.nextID, kind: Kind(condition.kind), text: condition.text, isExcluded: condition.isExcluded
      ))
      self.nextID += 1
    }
    self.conditions = conditions
    self.isCaseSensitive = saved.isCaseSensitive
    // 저장 값은 조건이 하나 이상이지만, 입력란이 늘 하나 있게 한 번 더 지킨다.
    if self.conditions.isEmpty {
      self.addCondition()
    }
  }

  /// 맞춤에 쓸 형태. 정규식을 읽지 못한 조건이 있으면 첫 조건의 문제를 돌려준다.
  func compiled() -> Result<CompiledLogFilter, LogFilterProblem> {
    var includes: [CompiledLogFilter.Matcher] = []
    var excludes: [CompiledLogFilter.Matcher] = []
    let caseOption: NSRegularExpression.Options = self.isCaseSensitive ? [] : [.caseInsensitive]
    for condition in self.conditions where !condition.text.isEmpty {
      let pattern = switch condition.kind {
      case .contains, .prefix: NSRegularExpression.escapedPattern(for: condition.text)
      case .regex: condition.text
      }
      guard let regex = try? NSRegularExpression(pattern: pattern, options: caseOption) else {
        return .failure(.invalidRegex(conditionID: condition.id))
      }
      let matcher = CompiledLogFilter.Matcher(regex: regex, isPrefix: condition.kind == .prefix)
      if condition.isExcluded {
        excludes.append(matcher)
      } else {
        includes.append(matcher)
      }
    }
    return .success(CompiledLogFilter(includes: includes, excludes: excludes))
  }

  private mutating func update(_ id: Int, _ change: (inout Condition) -> Void) {
    guard let index = self.conditions.firstIndex(where: { $0.id == id }) else { return }
    change(&self.conditions[index])
  }
}

/// 필터를 맞춤에 쓸 수 없는 이유.
public enum LogFilterProblem: Error, Hashable, Sendable {
  /// 이 조건의 정규식을 읽지 못했다 (`NSRegularExpression` 이 거부).
  case invalidRegex(conditionID: Int)
}
