import Core

/// 캔버스에서 클릭한 점(px)과 그 점의 노드들, 그중 고른 노드.
/// 스택은 Core `LayoutSnapshot.nodes(at:)` 결과 그대로(바깥→안쪽)이고 비어 있지 않다. 처음 고른 노드는 가장 안쪽(마지막)이다.
public struct LayoutPick: Hashable, Sendable {
  public let point: LayoutPoint
  /// 점을 포함하는 보이는 노드 번호, 바깥→안쪽.
  public let stack: [LayoutNode.ID]
  public private(set) var selected: LayoutNode.ID

  /// 스냅샷에서 점을 포함하는 노드를 골라 가장 안쪽을 고른다. 점이 화면 밖이거나 노드가 없으면 nil.
  init?(point: LayoutPoint, in snapshot: LayoutSnapshot) {
    let stack = snapshot.nodes(at: point)
    guard let innermost = stack.last else { return nil }
    self.point = point
    self.stack = stack
    self.selected = innermost
  }

  /// 스택에 든 번호면 고르고 true, 아니면 그대로 두고 false.
  @discardableResult
  mutating func select(_ id: LayoutNode.ID) -> Bool {
    guard self.stack.contains(id) else { return false }
    self.selected = id
    return true
  }
}
