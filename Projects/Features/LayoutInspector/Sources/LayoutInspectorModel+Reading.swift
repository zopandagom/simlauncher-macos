import Core
import Foundation

/// 상태를 바꾸지 않는 읽기. View 가 쓴다.
public extension LayoutInspectorModel {
  /// 창의 상태. 아직 열리지 않았으면 기본값.
  func window(for target: LayoutTarget) -> LayoutInspectorWindow {
    self.windows[target] ?? LayoutInspectorWindow()
  }

  /// 창 제목: "<기기 이름> 레이아웃". 이름은 스냅샷의 것, 스냅샷 전(처음 읽는 중·첫 실패)에는 창을 열 때 Client 에 물은 것
  /// (iOS), 그것도 모르면 기기 ID(Android 는 AVD 이름)로 여러 기기 창을 구별한다.
  func title(for target: LayoutTarget) -> String {
    let window = self.windows[target]
    let name = window?.snapshot?.deviceName ?? window?.deviceName ?? target.deviceID
    return LayoutInspectorText.windowTitle(deviceName: name)
  }

  /// 고른 노드. 고른 게 없으면 nil.
  func selectedNode(for target: LayoutTarget) -> LayoutNode? {
    guard let window = self.windows[target], let pick = window.pick else { return nil }
    return window.snapshot?.node(pick.selected)
  }

  /// 클릭한 점의 노드들, 바깥→안쪽. 고른 게 없으면 빈 배열.
  func stackNodes(for target: LayoutTarget) -> [LayoutNode] {
    guard let window = self.windows[target], let pick = window.pick, let snapshot = window.snapshot else { return [] }
    return pick.stack.compactMap { snapshot.node($0) }
  }
}
