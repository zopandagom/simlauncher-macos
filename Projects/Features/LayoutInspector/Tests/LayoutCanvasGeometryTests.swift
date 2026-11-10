import Core
import CoreGraphics
import Testing
@testable import LayoutInspectorFeature

struct LayoutCanvasGeometryTests {
  @Test("세로 화면을 넓은 캔버스에 맞추면 좌우에 여백을 두고 가운데 둔다")
  func pillarbox() {
    let geometry = LayoutCanvasGeometry(
      imageSize: LayoutSize(width: 1080, height: 2400),
      containerSize: CGSize(width: 1000, height: 600)
    )
    #expect(geometry.scale == 0.25)
    #expect(geometry.imageRect == CGRect(x: 365, y: 0, width: 270, height: 600))
  }

  @Test("가로 화면을 높은 캔버스에 맞추면 위아래에 여백을 두고, 창이 크면 확대한다")
  func letterboxAndUpscale() {
    let geometry = LayoutCanvasGeometry(
      imageSize: LayoutSize(width: 200, height: 100),
      containerSize: CGSize(width: 400, height: 1000)
    )
    #expect(geometry.scale == 2)
    #expect(geometry.imageRect == CGRect(x: 0, y: 400, width: 400, height: 200))
  }

  @Test("노드 사각형을 캔버스로 옮기고, 캔버스 점을 다시 px 로 되돌린다")
  func roundTrip() throws {
    let geometry = LayoutCanvasGeometry(
      imageSize: LayoutSize(width: 1080, height: 2400),
      containerSize: CGSize(width: 1000, height: 600)
    )
    let rect = geometry.viewRect(for: LayoutRect(x: 84, y: 104, width: 64, height: 64))
    #expect(rect == CGRect(x: 386, y: 26, width: 16, height: 16))
    let point = try #require(geometry.pixelPoint(fromView: CGPoint(x: rect.midX, y: rect.midY)))
    #expect(point == LayoutPoint(x: 116, y: 136))
  }

  @Test("이미지 밖(여백·오른쪽 아래 가장자리) 점은 nil 이다")
  func outsideImage() {
    let geometry = LayoutCanvasGeometry(
      imageSize: LayoutSize(width: 1080, height: 2400),
      containerSize: CGSize(width: 1000, height: 600)
    )
    #expect(geometry.pixelPoint(fromView: CGPoint(x: 100, y: 300)) == nil)
    #expect(geometry.pixelPoint(fromView: CGPoint(x: 635, y: 300)) == nil)
    #expect(geometry.pixelPoint(fromView: CGPoint(x: 400, y: 600)) == nil)
    #expect(geometry.pixelPoint(fromView: CGPoint(x: 365, y: 0)) == LayoutPoint(x: 0, y: 0))
  }

  @Test("캔버스 크기가 0 이면 배율 0 이고 모든 점이 nil 이다")
  func emptyContainer() {
    let geometry = LayoutCanvasGeometry(imageSize: LayoutSize(width: 1080, height: 2400), containerSize: .zero)
    #expect(geometry.scale == 0)
    #expect(geometry.pixelPoint(fromView: .zero) == nil)
  }
}
