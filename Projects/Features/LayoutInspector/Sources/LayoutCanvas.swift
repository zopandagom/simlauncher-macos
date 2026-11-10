import AppKit
import Core
import SwiftUI

/// 스크린샷을 비율을 지켜 가운데 두고, 그 위에 보이는 노드마다 얇은 테두리, 고른 노드는 굵은 강조와 옅은 채움을 그린다.
/// 테두리는 `Canvas` 하나로 그려 노드가 수천 개여도 View 수가 늘지 않는다. 이미지 밖에 걸친 테두리는 이미지 경계에서 자른다.
/// 클릭한 점은 스크린샷 px 로 바꿔 넘기고, 이미지 밖 클릭은 무시한다.
struct LayoutCanvas: View {
  let image: NSImage?
  let snapshot: LayoutSnapshot
  let selectedID: LayoutNode.ID?
  let clicked: (LayoutPoint) -> Void

  var body: some View {
    GeometryReader { proxy in
      let geometry = LayoutCanvasGeometry(imageSize: self.snapshot.pixelSize, containerSize: proxy.size)
      ZStack(alignment: .topLeading) {
        if let image = self.image {
          Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: geometry.imageRect.width, height: geometry.imageRect.height)
            .offset(x: geometry.imageRect.minX, y: geometry.imageRect.minY)
        }
        Canvas { context, _ in
          self.drawOutlines(in: &context, geometry: geometry)
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
      }
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
      .contentShape(Rectangle())
      .onTapGesture(coordinateSpace: .local) { location in
        if let point = geometry.pixelPoint(fromView: location) {
          self.clicked(point)
        }
      }
    }
    .clipped()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(LayoutInspectorText.canvasAccessibilityLabel)
  }

  private func drawOutlines(in context: inout GraphicsContext, geometry: LayoutCanvasGeometry) {
    context.clip(to: Path(geometry.imageRect))
    var outlines = Path()
    var selected: CGRect?
    for node in self.snapshot.visibleNodes {
      let rect = geometry.viewRect(for: node.frame)
      if node.id == self.selectedID {
        selected = rect
      } else {
        outlines.addRect(rect)
      }
    }
    context.stroke(outlines, with: .color(Color.accentColor.opacity(0.45)), lineWidth: 1)
    if let selected {
      context.fill(Path(selected), with: .color(Color.orange.opacity(0.15)))
      context.stroke(Path(selected), with: .color(Color.orange), lineWidth: 2)
    }
  }
}
