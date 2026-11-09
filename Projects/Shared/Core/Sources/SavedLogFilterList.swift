/// 저장된 로그 필터 배열(`LogFilters`)의 규칙. 항목은 저장 배열과 같은 인덱스로 받고, 읽지 못한 항목은 nil 이다.
/// 읽지 못한 항목은 목록에 보이지 않고 같은 이름 판정·상한에도 들지 않지만, 변경을 적용해도 같은 자리에 원래 값 그대로 남는다.
public enum SavedLogFilterList {
  /// 저장 배열에 할 변경.
  public enum Change: Hashable, Sendable {
    /// 끝에 붙인다.
    case append(SavedLogFilter)
    /// `index` 자리를 바꾸고 `removing`(오름차순, `index` 미포함) 자리를 지운다.
    case replace(index: Int, with: SavedLogFilter, removing: [Int])
    /// 자리를 지운다 (오름차순).
    case remove([Int])

    /// 원본 배열에 적용한다. 고치지 않는 자리는 원소 그대로 두고(읽지 못한 항목 보존), 지우기는 뒤 인덱스부터 한다.
    /// 범위 밖 인덱스는 건너뛴다.
    public func applied<Item>(to items: [Item], encode: (SavedLogFilter) -> Item) -> [Item] {
      var result = items
      switch self {
      case let .append(filter):
        result.append(encode(filter))
      case let .replace(index, filter, removing):
        if result.indices.contains(index) {
          result[index] = encode(filter)
        }
        Self.remove(removing.filter { $0 != index }, from: &result)
      case let .remove(indices):
        Self.remove(indices, from: &result)
      }
      return result
    }

    private static func remove(_ indices: [Int], from items: inout [some Any]) {
      for index in Set(indices).sorted(by: >) where items.indices.contains(index) {
        items.remove(at: index)
      }
    }
  }

  /// 저장하지 않은 이유.
  public enum SaveRefusal: Error, Hashable, Sendable {
    /// 같은 이름(대소문자 무시)이 있는데 덮어쓰지 않기로 했다.
    case sameName
    /// 보이는 목록이 상한(`SavedLogFilter.maxCount`)이라 새 이름을 더하지 않았다.
    case limitReached
  }

  /// 읽은 항목을 저장 순서대로, 같은 이름(대소문자 무시)은 앞 것만.
  public static func visible(_ items: [SavedLogFilter?]) -> [SavedLogFilter] {
    var result: [SavedLogFilter] = []
    for case let filter? in items where !result.contains(where: { SavedLogFilter.isSameName($0.name, filter.name) }) {
      result.append(filter)
    }
    return result
  }

  /// 저장 변경. 같은 이름(읽은 항목)이 있으면 `replacingSameName` 이 거짓이면 `.sameName`, 참이면 첫 자리를 바꾸고 나머지 같은 이름 자리를
  /// 지운다. 없으면 보이는 목록이 상한 이상이면 `.limitReached`, 아니면 끝에 붙인다.
  /// 같은 이름 판정이 먼저라 상한이어도 같은 이름 덮어쓰기는 된다 (개수를 늘리지 않는다).
  public static func saveChange(
    _ filter: SavedLogFilter,
    replacingSameName: Bool,
    in items: [SavedLogFilter?]
  ) -> Result<Change, SaveRefusal> {
    let same = self.indicesOfSameName(filter.name, in: items)
    if let first = same.first {
      guard replacingSameName else {
        return .failure(.sameName)
      }
      return .success(.replace(index: first, with: filter, removing: Array(same.dropFirst())))
    }
    guard self.visible(items).count < SavedLogFilter.maxCount else {
      return .failure(.limitReached)
    }
    return .success(.append(filter))
  }

  /// 같은 이름(대소문자 무시) 읽은 항목 자리를 모두 지운다. 없으면 nil (쓰지 않는다).
  public static func removeChange(named name: String, in items: [SavedLogFilter?]) -> Change? {
    let same = self.indicesOfSameName(name, in: items)
    return same.isEmpty ? nil : .remove(same)
  }

  private static func indicesOfSameName(_ name: String, in items: [SavedLogFilter?]) -> [Int] {
    items.indices.filter { index in
      items[index].map { SavedLogFilter.isSameName($0.name, name) } ?? false
    }
  }
}
