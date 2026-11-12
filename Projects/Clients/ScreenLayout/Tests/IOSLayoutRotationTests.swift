import Core
import ScreenLayoutInterface
import Testing
@testable import ScreenLayoutImpl

/// 화면을 돌린 iPad 의 SpringBoard: 세로 좌표 → 화면 좌표 (값은 실측 Xcode 27.2·iOS 27.0 iPad Pro 11 (M5) 홈 화면, scale 2).
struct IOSLayoutRotationTests {
  typealias Node = LayoutRunnerProtocol.Node

  static func node(_ depth: Int, _ type: Int, _ frame: [Double], label: String? = nil) -> Node {
    IOSLayoutConversionTests.node(depth, type, frame, label: label)
  }

  /// 루트 · 세로 창 · px 창(빠짐) · 상태 막대 · Safari 아이콘.
  static func home(root: [Double], statusBar: [Double], safari: [Double]) -> [Node] {
    [
      self.node(0, 2, root),
      self.node(1, 4, [0, 0, 834, 1210], label: "창"),
      self.node(2, 25, statusBar, label: "상태 막대"),
      self.node(2, 44, safari, label: "Safari"),
      self.node(1, 4, [0, 0, 1668, 2420]),
      self.node(2, 1, [0, 0, 1668, 2420]),
    ]
  }

  static func convert(_ nodes: [Node], system: Bool = true) throws -> [LayoutNode] {
    try IOSLayoutConversion.nodes(from: nodes, scale: 2, system: system)
  }

  @Test("가로 좌: 상태 막대가 세로 좌표의 오른쪽 끝이면 화면 x = y, 화면 y = W − x − w")
  func landscapeLeft() throws {
    let nodes = try Self.convert(Self.home(
      root: [0, 0, 1210, 834], statusBar: [802, 0, 32, 1210], safari: [28, 440, 68, 68]
    ))
    #expect(nodes.map(\.label) == [nil, "창", "상태 막대", "Safari"])
    #expect(nodes.map(\.frame) == [
      LayoutRect(x: 0, y: 0, width: 2420, height: 1668),
      LayoutRect(x: 0, y: 0, width: 2420, height: 1668),
      LayoutRect(x: 0, y: 0, width: 2420, height: 64),
      LayoutRect(x: 880, y: 1476, width: 136, height: 136),
    ])
  }

  @Test("가로 우: 상태 막대가 세로 좌표의 왼쪽 끝이면 화면 x = H − y − h, 화면 y = x (가로 좌와 같은 자리)")
  func landscapeRight() throws {
    let nodes = try Self.convert(Self.home(
      root: [0, 0, 1210, 834], statusBar: [0, 0, 32, 1210], safari: [738, 702, 68, 68]
    ))
    #expect(nodes.map(\.frame) == [
      LayoutRect(x: 0, y: 0, width: 2420, height: 1668),
      LayoutRect(x: 0, y: 0, width: 2420, height: 1668),
      LayoutRect(x: 0, y: 0, width: 2420, height: 64),
      LayoutRect(x: 880, y: 1476, width: 136, height: 136),
    ])
  }

  @Test("거꾸로 세로: 루트가 세로 모양이어도 상태 막대가 아래면 180° 돌린다 (세로와 같은 자리)")
  func upsideDown() throws {
    let nodes = try Self.convert(Self.home(
      root: [0, 0, 834, 1210], statusBar: [0, 1178, 834, 32], safari: [514, 27.5, 68, 68]
    ))
    #expect(nodes.map(\.frame) == [
      LayoutRect(x: 0, y: 0, width: 1668, height: 2420),
      LayoutRect(x: 0, y: 0, width: 1668, height: 2420),
      LayoutRect(x: 0, y: 0, width: 1668, height: 64),
      LayoutRect(x: 504, y: 2229, width: 136, height: 136),
    ])
  }

  @Test("세로: 상태 막대가 위면 그대로")
  func portrait() throws {
    let input = Self.home(root: [0, 0, 834, 1210], statusBar: [0, 0, 834, 32], safari: [252, 1114.5, 68, 68])
    let nodes = try Self.convert(input)
    #expect(nodes.map(\.frame) == [
      LayoutRect(x: 0, y: 0, width: 1668, height: 2420),
      LayoutRect(x: 0, y: 0, width: 1668, height: 2420),
      LayoutRect(x: 0, y: 0, width: 1668, height: 64),
      LayoutRect(x: 504, y: 2229, width: 136, height: 136),
    ])
  }

  @Test("앱 전환기: 루트까지 세로 크기로 와도 가로 화면 크기로 돌린다")
  func switcherRootInPortraitSize() throws {
    let nodes = try Self.convert(Self.home(
      root: [0, 0, 834, 1210], statusBar: [802, 0, 32, 1210], safari: [28, 440, 68, 68]
    ))
    #expect(nodes[0].frame == LayoutRect(x: 0, y: 0, width: 2420, height: 1668))
    #expect(nodes[3].frame == LayoutRect(x: 880, y: 1476, width: 136, height: 136))
  }

  @Test("iPhone 가로: 홈 화면이 돌지 않아 상태 막대가 위에 있으면 그대로")
  func iPhoneLandscapeHome() throws {
    let nodes = try Self.convert([
      Self.node(0, 2, [0, 0, 402, 874]),
      Self.node(1, 4, [0, 0, 402, 874]),
      Self.node(2, 25, [0, 0, 402, 54]),
      Self.node(2, 44, [20, 700, 64, 64]),
    ])
    #expect(nodes[3].frame == LayoutRect(x: 40, y: 1400, width: 128, height: 128))
  }

  @Test("iPhone Duo: 상태 막대가 화면 크기(띠가 아님)면 방향을 정하지 않고 그대로")
  func duoStatusBarIsNotStrip() throws {
    let nodes = try Self.convert([
      Self.node(0, 2, [0, 0, 466, 678]),
      Self.node(1, 4, [0, 0, 466, 678]),
      Self.node(2, 25, [0, 0, 466, 678]),
      Self.node(2, 44, [400, 450, 60, 60]),
    ])
    #expect(nodes[3].frame == LayoutRect(x: 800, y: 900, width: 120, height: 120))
  }

  @Test("상태 막대가 없으면 그대로")
  func noStatusBar() throws {
    let input = Self.home(root: [0, 0, 1210, 834], statusBar: [0, 0, 0, 0], safari: [28, 440, 68, 68])
      .filter { $0.type != 25 }
    let nodes = try Self.convert(input)
    #expect(nodes.map(\.frame) == [
      LayoutRect(x: 0, y: 0, width: 2420, height: 1668),
      LayoutRect(x: 0, y: 0, width: 1668, height: 2420),
      LayoutRect(x: 56, y: 880, width: 136, height: 136),
    ])
  }

  @Test("앱 스냅샷은 세로 띠 상태 막대가 있어도 돌리지 않는다 (앱 창은 화면 좌표)")
  func appSnapshotIsNotRotated() throws {
    let nodes = try Self.convert(
      [
        Self.node(0, 2, [0, 0, 1210, 834]),
        Self.node(1, 25, [802, 0, 32, 834]),
        Self.node(1, 9, [28, 440, 68, 68]),
      ],
      system: false
    )
    #expect(nodes[2].frame == LayoutRect(x: 56, y: 880, width: 136, height: 136))
  }

  static let rotationCases: [([Double], IOSLayoutConversion.ScreenRotation)] = [
    ([0, 0, 834, 32], .portrait),
    ([0, 0, 834.5, 32], .portrait),
    ([0, 1178, 834, 32], .upsideDown),
    ([0, 1178.5, 834, 32], .upsideDown),
    ([802, 0, 32, 1210], .landscapeLeft),
    ([0, 0, 32, 1210], .landscapeRight),
    ([0.5, 0, 32, 1210], .landscapeRight),
    ([0, 1001.6, 834, 208.4], .upsideDown),
    ([0, 0, 208.4, 1210], .landscapeRight),
    ([0, 1001.5, 834, 208.5], .portrait),
    ([0, 0, 208.5, 1210], .portrait),
    ([0, 0, 833, 32], .portrait),
    ([0, 500, 834, 32], .portrait),
    ([1, 0, 32, 1210], .portrait),
    ([0, 0, 32, 1209], .portrait),
  ]

  @Test(
    "방향 판정: 띠(짧은 변 < 세로 폭의 ¼)가 세로 크기의 한 변 전체(0.5 안)에 붙어 있을 때만, 아니면 세로",
    arguments: rotationCases
  )
  func rotationBoundaries(frame: [Double], expected: IOSLayoutConversion.ScreenRotation) {
    let root = Self.node(0, 2, [0, 0, 1210, 834])
    #expect(IOSLayoutConversion.rotation(of: [Self.node(2, 25, frame)], root: root) == expected)
  }

  @Test("방향 판정: 띠가 아닌 상태 막대는 건너뛰고 처음 띠로 정한다, 다른 종류의 띠는 보지 않는다")
  func firstStripWins() {
    let root = Self.node(0, 2, [0, 0, 834, 1210])
    let nodes = [
      Self.node(2, 1, [0, 0, 32, 1210]),
      Self.node(2, 25, [0, 0, 834, 1210]),
      Self.node(3, 25, [802, 0, 32, 1210]),
      Self.node(3, 25, [0, 0, 32, 1210]),
    ]
    #expect(IOSLayoutConversion.rotation(of: nodes, root: root) == .landscapeLeft)
  }

  @Test("루트가 여럿이면 루트마다 자기 하위의 상태 막대로 정한다")
  func perRootRotation() throws {
    let nodes = try Self.convert([
      Self.node(0, 2, [0, 0, 834, 1210]),
      Self.node(1, 25, [0, 1178, 834, 32]),
      Self.node(0, 2, [0, 0, 834, 1210]),
      Self.node(1, 9, [0, 0, 10, 10]),
    ])
    #expect(nodes[1].frame == LayoutRect(x: 0, y: 0, width: 1668, height: 64))
    #expect(nodes[3].frame == LayoutRect(x: 0, y: 0, width: 20, height: 20))
  }
}
