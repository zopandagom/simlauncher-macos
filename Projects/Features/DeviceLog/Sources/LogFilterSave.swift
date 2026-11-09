import Core
import Foundation
import PreferencesInterface

/// "지금 필터 저장…" 을 막는 이유. nil 이면 저장할 수 있다.
public enum LogFilterSaveBlock: Hashable, Sendable {
  /// 관리자가 목록을 강제했다 (`SavedLogFilterSetting.isLocked`).
  case locked
  /// 글자가 있는 조건이 없다.
  case emptyFilter
  /// 읽을 수 없는 정규식이 있다 (`DeviceLogWindow.filterProblem`).
  case invalidRegex
  /// 글자가 있는 조건이 `SavedLogFilter.maxConditions` 개를 넘는다.
  case tooManyConditions
  /// 조건 글자가 `SavedLogFilter.maxTextLength` 자를 넘는다.
  case textTooLong

  /// 순서: locked → emptyFilter → invalidRegex → tooManyConditions → textTooLong.
  /// 50개 상한은 이름에 달려 있어(같은 이름 덮어쓰기는 된다) 여기 넣지 않는다 (`LogFilterSaveDraft.isOverLimit`).
  static func reason(filter: LogFilter, problem: LogFilterProblem?, saved: SavedLogFilterSetting) -> Self? {
    if saved.isLocked {
      return .locked
    }
    let conditions = filter.savedConditions()
    if conditions.isEmpty {
      return .emptyFilter
    }
    if problem != nil {
      return .invalidRegex
    }
    switch SavedLogFilter.conditionsProblem(conditions) {
    case .tooManyConditions: return .tooManyConditions
    case .textTooLong: return .textTooLong
    // 빈 조건을 뺐으므로 나오지 않는다.
    case .noConditions, .emptyText: return .emptyFilter
    case .emptyName, .nameTooLong, nil: return nil
    }
  }
}

/// 창 하나의 저장 시트 상태: 이름 입력과 같은 이름 확인.
public struct LogFilterSaveDraft: Hashable, Sendable {
  public enum Step: Hashable, Sendable {
    case naming
    /// 같은 이름 확인 중. existingName 은 저장된 표기(대소문자가 다를 수 있다).
    case confirmingReplace(existingName: String)
  }

  /// 입력 그대로 (저장 때 앞뒤 공백을 자른다).
  public private(set) var name: String
  public private(set) var step: Step

  /// 이름 규칙 문제. emptyName 은 안내 없이 저장 버튼만 끄고, nameTooLong 은 시트가 안내한다.
  public var nameProblem: SavedLogFilterProblem? {
    SavedLogFilter.nameProblem(self.name)
  }

  init(name: String = "", step: Step = .naming) {
    self.name = name
    self.step = step
  }

  mutating func setName(_ name: String) {
    self.name = name
  }

  mutating func setStep(_ step: Step) {
    self.step = step
  }

  /// 이 이름으로 저장하면 50개 상한에 걸린다: 보이는 목록이 상한 이상이고 같은 이름(대소문자 무시)이 없다.
  /// 같은 이름은 덮어쓰기라 개수가 늘지 않아 걸리지 않는다. 빈 이름은 거짓 (`nameProblem` 이 막는다).
  static func isOverLimit(name: String, saved: SavedLogFilterSetting) -> Bool {
    guard !SavedLogFilter.normalizedName(name).isEmpty else { return false }
    return saved.filters.count >= SavedLogFilter.maxCount
      && !saved.filters.contains { SavedLogFilter.isSameName($0.name, name) }
  }
}
