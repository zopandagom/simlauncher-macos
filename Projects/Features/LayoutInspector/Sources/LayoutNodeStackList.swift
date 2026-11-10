import Core
import SwiftUI

/// "이 위치의 뷰": 클릭한 점을 포함하는 노드, 바깥→안쪽. 고른 행이 선택 표시되고, 다른 행을 고르면 Model 에 알린다.
/// 행은 짧은 종류(마지막 `.` 뒤)와 식별자(없으면 텍스트·설명) 한 줄이다.
struct LayoutNodeStackList: View {
  let model: LayoutInspectorModel
  let target: LayoutTarget

  var body: some View {
    let nodes = self.model.stackNodes(for: self.target)
    VStack(alignment: .leading, spacing: 6) {
      Text(LayoutInspectorText.stackTitle)
        .font(.headline)
      List(
        selection: Binding(
          get: { self.model.window(for: self.target).pick?.selected },
          set: { id in
            if let id {
              self.model.stackNodeSelected(id, in: self.target)
            }
          }
        )
      ) {
        ForEach(nodes) { node in
          self.row(node)
            .tag(node.id)
        }
      }
      .listStyle(.bordered)
      .overlay {
        if nodes.isEmpty {
          Text(LayoutInspectorText.noPickGuide)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
        }
      }
    }
  }

  private func row(_ node: LayoutNode) -> some View {
    HStack(spacing: 6) {
      Text(verbatim: Self.shortType(node.type))
        .fontWeight(.medium)
      if let detail = Self.shortDetail(node) {
        Text(verbatim: detail)
          .foregroundStyle(.secondary)
      }
    }
    .lineLimit(1)
    .truncationMode(.tail)
  }

  /// `android.widget.TextView` → `TextView`.
  static func shortType(_ type: String) -> String {
    type.split(separator: ".").last.map(String.init) ?? type
  }

  /// 식별자(`package:id/name` 이면 `name`), 없으면 텍스트, 없으면 설명.
  static func shortDetail(_ node: LayoutNode) -> String? {
    if let identifier = node.identifier {
      return identifier.split(separator: "/").last.map(String.init) ?? identifier
    }
    return node.text ?? node.label
  }
}
