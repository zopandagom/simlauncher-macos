import Foundation
import Testing
@testable import Core

struct LayoutSnapshotTests {
  /// 1080×2400 화면.
  static func snapshot(_ nodes: [LayoutNode], width: Int = 1080, height: Int = 2400) -> LayoutSnapshot {
    LayoutSnapshot(
      deviceName: "Pixel",
      capturedAt: Date(timeIntervalSince1970: 0),
      screenshotPNG: Data(),
      pixelSize: LayoutSize(width: width, height: height),
      unit: .dp,
      pixelsPerUnit: 2.625,
      nodes: nodes,
      appIdentifier: nil,
      isSystemScreen: false
    )
  }

  /// `[left,top][right,bottom]` 모양으로 노드를 만든다.
  static func node(
    _ id: Int,
    depth: Int = 1,
    parent: Int? = 0,
    _ left: Double,
    _ top: Double,
    _ right: Double,
    _ bottom: Double
  )
    -> LayoutNode
  {
    LayoutNode(
      id: id,
      depth: depth,
      parentID: parent,
      frame: LayoutRect(x: left, y: top, width: right - left, height: bottom - top),
      type: "android.view.View"
    )
  }

  static let root = Self.node(0, depth: 0, parent: nil, 0, 0, 1080, 2400)

  // MARK: - visibleNodes

  @Test("크기 0·뒤집힌 bounds·화면 완전 밖 노드는 숨기고, 일부만 걸친 노드는 보인다")
  func visibleNodes() {
    let snapshot = Self.snapshot([
      Self.root,
      Self.node(1, 100, 100, 100, 300), // 너비 0
      Self.node(2, 0, 294, 2400, 154), // 뒤집힌 bounds (rot1 모양)
      Self.node(3, 1080, 0, 1200, 100), // 오른쪽 밖 (가장자리에서 시작)
      Self.node(4, 0, 2400, 100, 2500), // 아래 밖
      Self.node(5, -200, -200, 0, 0), // 왼쪽 위 밖 (음수, 가장자리에서 끝)
      Self.node(6, -50, 2300, 50, 2450), // 일부만 걸침
      Self.node(7, 10, 10, 20, 20),
    ])

    #expect(snapshot.visibleNodes.map(\.id) == [0, 6, 7])
    #expect(snapshot.nodes.count == 8)
  }

  @Test("node(_:) 는 번호의 노드, 없으면 nil")
  func nodeLookup() {
    let snapshot = Self.snapshot([Self.root, Self.node(1, 0, 0, 10, 10)])

    #expect(snapshot.node(1)?.frame.width == 10)
    #expect(snapshot.node(2) == nil)
    #expect(snapshot.node(-1) == nil)
  }

  // MARK: - nodes(at:)

  @Test("점을 포함하는 노드를 넓이 내림차순으로, 마지막이 가장 작은 노드")
  func stackByArea() {
    let snapshot = Self.snapshot([
      Self.root,
      Self.node(1, 0, 0, 1080, 168),
      Self.node(2, depth: 2, parent: 1, 64, 84, 169, 189),
      Self.node(3, depth: 3, parent: 2, 85, 105, 148, 168),
      Self.node(4, 500, 500, 600, 600),
    ])

    #expect(snapshot.nodes(at: LayoutPoint(x: 100, y: 150)) == [0, 1, 2, 3])
  }

  @Test("넓이가 같으면 얕은 노드가 먼저, 깊이도 같으면 번호 순 (Compose 겹침 모양)")
  func stackTieBreak() {
    let snapshot = Self.snapshot([
      Self.root,
      Self.node(1, depth: 9, parent: 0, 446, 625, 635, 772),
      Self.node(2, depth: 8, parent: 0, 446, 625, 635, 772),
      Self.node(3, depth: 8, parent: 0, 446, 625, 635, 772),
    ])

    #expect(snapshot.nodes(at: LayoutPoint(x: 540, y: 700)) == [0, 2, 3, 1])
  }

  @Test("반열림: 왼쪽·위 가장자리는 포함, 오른쪽·아래 가장자리는 제외")
  func halfOpenEdges() {
    let snapshot = Self.snapshot([Self.root, Self.node(1, 100, 100, 200, 200)])

    #expect(snapshot.nodes(at: LayoutPoint(x: 100, y: 100)) == [0, 1])
    #expect(snapshot.nodes(at: LayoutPoint(x: 199.9, y: 199.9)) == [0, 1])
    #expect(snapshot.nodes(at: LayoutPoint(x: 200, y: 150)) == [0])
    #expect(snapshot.nodes(at: LayoutPoint(x: 150, y: 200)) == [0])
  }

  @Test("숨긴 노드는 스택에 없다")
  func hiddenExcluded() {
    let snapshot = Self.snapshot([
      Self.root,
      Self.node(1, 0, 294, 2400, 154), // 뒤집힘
      Self.node(2, 10, 10, 10, 50), // 너비 0
    ])

    #expect(snapshot.nodes(at: LayoutPoint(x: 10, y: 20)) == [0])
    #expect(snapshot.nodes(at: LayoutPoint(x: 100, y: 200)) == [0])
  }

  @Test("화면 밖 점은 빈 배열 (화면 밖으로 삐져나온 노드 위여도)")
  func pointOutsideScreen() {
    let snapshot = Self.snapshot([Self.root, Self.node(1, -50, -50, 50, 50)])

    #expect(snapshot.nodes(at: LayoutPoint(x: -10, y: 10)).isEmpty)
    #expect(snapshot.nodes(at: LayoutPoint(x: 1080, y: 10)).isEmpty)
    #expect(snapshot.nodes(at: LayoutPoint(x: 10, y: 2400)).isEmpty)
    #expect(snapshot.nodes(at: LayoutPoint(x: 10, y: 10)) == [0, 1])
  }

  @Test("형제가 겹치면(조상 사슬이 아니어도) 작은 쪽이 마지막")
  func overlappingSiblings() {
    let snapshot = Self.snapshot([
      Self.root,
      Self.node(1, 0, 0, 500, 500),
      Self.node(2, 100, 100, 300, 300),
    ])

    #expect(snapshot.nodes(at: LayoutPoint(x: 150, y: 150)) == [0, 1, 2])
  }

  @Test("노드가 없으면 보이는 노드도 스택도 비었다")
  func empty() {
    let snapshot = Self.snapshot([])

    #expect(snapshot.visibleNodes.isEmpty)
    #expect(snapshot.nodes(at: LayoutPoint(x: 10, y: 10)).isEmpty)
  }
}
