import Core
import CoreGraphics

/// 스크린샷(px)을 캔버스(pt)에 비율을 지켜 맞추고 가운데 두는 변환. 창이 크면 확대도 한다.
/// 레티나 배율은 SwiftUI 좌표(pt)에서만 계산하므로 보지 않는다.
struct LayoutCanvasGeometry: Hashable {
  /// px 하나의 pt 수. 이미지·캔버스 크기가 0 이면 0.
  let scale: Double
  /// 캔버스 안 이미지 자리 (pt).
  let imageRect: CGRect

  init(imageSize: LayoutSize, containerSize: CGSize) {
    let imageWidth = Double(imageSize.width)
    let imageHeight = Double(imageSize.height)
    guard imageWidth > 0, imageHeight > 0, containerSize.width > 0, containerSize.height > 0 else {
      self.scale = 0
      self.imageRect = .zero
      return
    }
    let scale = min(containerSize.width / imageWidth, containerSize.height / imageHeight)
    let width = imageWidth * scale
    let height = imageHeight * scale
    self.scale = scale
    self.imageRect = CGRect(
      x: (containerSize.width - width) / 2,
      y: (containerSize.height - height) / 2,
      width: width,
      height: height
    )
  }

  /// 노드 사각형(px)의 캔버스 자리(pt).
  func viewRect(for frame: LayoutRect) -> CGRect {
    CGRect(
      x: self.imageRect.minX + frame.x * self.scale,
      y: self.imageRect.minY + frame.y * self.scale,
      width: frame.width * self.scale,
      height: frame.height * self.scale
    )
  }

  /// 캔버스 점(pt)의 스크린샷 px. 이미지 밖이면 nil (클릭을 무시한다).
  func pixelPoint(fromView point: CGPoint) -> LayoutPoint? {
    guard self.scale > 0,
          point.x >= self.imageRect.minX, point.x < self.imageRect.maxX,
          point.y >= self.imageRect.minY, point.y < self.imageRect.maxY
    else { return nil }
    return LayoutPoint(
      x: (point.x - self.imageRect.minX) / self.scale,
      y: (point.y - self.imageRect.minY) / self.scale
    )
  }
}
