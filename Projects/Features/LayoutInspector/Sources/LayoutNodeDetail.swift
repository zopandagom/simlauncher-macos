import Core
import SwiftUI

/// 고른 노드의 속성: 종류(전체 이름)·식별자·텍스트·설명과 x·y·너비·높이(단위 값 + px). 글자는 고를 수 있다.
/// 밀도(배율)를 읽지 못했으면 px 만 보이고 그 이유를 아래에 보인다.
struct LayoutNodeDetail: View {
  let node: LayoutNode?
  let unit: LayoutUnit
  let pixelsPerUnit: Double?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(LayoutInspectorText.detailTitle)
        .font(.headline)
      if let node = self.node {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
          self.row(LayoutInspectorText.typeLabel, node.type)
          self.row(LayoutInspectorText.identifierLabel, node.identifier)
          self.row(LayoutInspectorText.textLabel, node.text)
          self.row(LayoutInspectorText.descriptionLabel, node.label)
          Divider()
            .gridCellUnsizedAxes(.horizontal)
          self.row("x", self.value(node.frame.x))
          self.row("y", self.value(node.frame.y))
          self.row(LayoutInspectorText.widthLabel, self.value(node.frame.width))
          self.row(LayoutInspectorText.heightLabel, self.value(node.frame.height))
        }
        .textSelection(.enabled)
      } else {
        Text(LayoutInspectorText.noPickGuide)
          .foregroundStyle(.secondary)
      }
      if self.pixelsPerUnit == nil {
        Text(LayoutInspectorText.densityUnavailable)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func value(_ pixels: Double) -> String {
    LayoutValueFormat.value(pixels, unit: self.unit, pixelsPerUnit: self.pixelsPerUnit)
  }

  /// 이름 칸과 값 칸. 값이 없으면 `—`.
  private func row(_ name: String, _ value: String?) -> some View {
    GridRow {
      Text(verbatim: name)
        .foregroundStyle(.secondary)
        .gridColumnAlignment(.trailing)
      Text(verbatim: value ?? "—")
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
