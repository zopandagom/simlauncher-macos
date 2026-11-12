import Core
import Foundation
import ScreenLayoutInterface
import SimulatorInterface
import Testing
@testable import ScreenLayoutImpl

struct IOSLayoutConversionTests {
  typealias Node = LayoutRunnerProtocol.Node

  static func node(
    _ depth: Int,
    _ type: Int = 1,
    _ frame: [Double] = [0, 0, 10, 10],
    identifier: String? = nil,
    label: String? = nil,
    title: String? = nil,
    value: String? = nil
  ) -> Node {
    Node(
      depth: depth, type: type, x: frame[0], y: frame[1], width: frame[2], height: frame[3],
      identifier: identifier, label: label, title: title, value: value
    )
  }

  @Test("ElementType 이름 표: 0·9·48·82 와 표 밖")
  func typeNames() {
    #expect(IOSLayoutConversion.elementTypeNames.count == 83)
    #expect(IOSLayoutConversion.typeName(0) == "Any")
    #expect(IOSLayoutConversion.typeName(9) == "Button")
    #expect(IOSLayoutConversion.typeName(48) == "StaticText")
    #expect(IOSLayoutConversion.typeName(82) == "StatusItem")
    #expect(IOSLayoutConversion.typeName(83) == "ElementType(83)")
    #expect(IOSLayoutConversion.typeName(-1) == "ElementType(-1)")
  }

  @Test("pt × scale = px, 부모는 깊이 스택, id 는 순서대로")
  func scaleAndParents() throws {
    let nodes = try IOSLayoutConversion.nodes(
      from: [
        Self.node(0, 2, [0, 0, 402, 874]),
        Self.node(1, 3, [10, 20, 100, 50]),
        Self.node(2, 9, [12, 22, 30, 10.5]),
        Self.node(1, 48, [0, 800, 402, 74]),
      ],
      scale: 3,
      system: false
    )
    #expect(nodes.map(\.id) == [0, 1, 2, 3])
    #expect(nodes.map(\.parentID) == [nil, 0, 1, 0])
    #expect(nodes.map(\.depth) == [0, 1, 2, 1])
    #expect(nodes[0].frame == LayoutRect(x: 0, y: 0, width: 1206, height: 2622))
    #expect(nodes[2].frame == LayoutRect(x: 36, y: 66, width: 90, height: 31.5))
    #expect(nodes.map(\.type) == ["Application", "Group", "Button", "StaticText"])
  }

  @Test("루트가 여럿이면 각자 부모 없음 (앞 앱 여럿)")
  func multipleRoots() throws {
    let nodes = try IOSLayoutConversion.nodes(
      from: [Self.node(0), Self.node(1), Self.node(0), Self.node(1)],
      scale: 2,
      system: false
    )
    #expect(nodes.map(\.parentID) == [nil, 0, nil, 2])
  }

  @Test("깊이 1 의 px 창(루트 × scale)은 하위와 함께 빼고 id 를 다시 매긴다 (SpringBoard 모양)")
  func pixelWindows() throws {
    let nodes = try IOSLayoutConversion.nodes(
      from: [
        Self.node(0, 2, [0, 0, 402, 874]),
        Self.node(1, 4, [0, 0, 1206, 2622]),
        Self.node(2, 1, [0, 0, 1206, 2622]),
        Self.node(1, 4, [0, 0, 402, 874], label: "홈"),
        Self.node(2, 44, [20, 60, 64, 64], label: "설정"),
        Self.node(1, 4, [0, 0, 1206.4, 2621.6]),
      ],
      scale: 3,
      system: true
    )
    #expect(nodes.map(\.id) == [0, 1, 2])
    #expect(nodes.map(\.parentID) == [nil, 0, 1])
    #expect(nodes.map(\.label) == [nil, "홈", "설정"])
  }

  @Test("화면이 둘인 기기(iPhone Duo)의 SpringBoard: 안쪽 화면의 pt·px 창은 하위와 함께 빼고 바깥 화면 창만 남긴다")
  func otherDisplayWindows() throws {
    let nodes = try IOSLayoutConversion.nodes(
      from: [
        Self.node(0, 2, [0, 0, 466, 678]),
        Self.node(1, 4, [0, 0, 669, 951]),
        Self.node(2, 1, [0, 0, 669, 951]),
        Self.node(3, 44, [560, 840, 64, 64], label: "Safari"),
        Self.node(1, 4, [0, 0, 466, 678], label: "홈"),
        Self.node(2, 44, [400, 450, 60, 60], label: "Safari"),
        Self.node(1, 4, [0, 0, 2007, 2853]),
        Self.node(2, 1, [0, 0, 2007, 2853]),
        Self.node(1, 4, [0, 0, 1398, 2034]),
      ],
      scale: 3,
      system: true
    )
    #expect(nodes.map(\.id) == [0, 1, 2])
    #expect(nodes.map(\.parentID) == [nil, 0, 1])
    #expect(nodes.map(\.label) == [nil, "홈", "Safari"])
    #expect(nodes[2].frame == LayoutRect(x: 1200, y: 1350, width: 180, height: 180))
  }

  @Test("루트 안에 (가로·세로를 바꿔서도) 들어가지 않는 창만 빼고, 0.5 안 창·가로 iPad SpringBoard 의 세로 창은 남긴다")
  func oversizedBoundary() throws {
    let nodes = try IOSLayoutConversion.nodes(
      from: [
        Self.node(0, 2, [0, 0, 402, 874]),
        Self.node(1, 4, [0, 0, 402.5, 874.5], label: "경계"),
        Self.node(1, 7, [50, 300, 300, 200], label: "알림"),
        Self.node(1, 4, [0, 0, 403, 874]),
        Self.node(1, 4, [0, 0, 402, 875]),
        Self.node(2, 9, [0, 0, 10, 10], label: "큰 창의 하위"),
        Self.node(1, 4, [0, 0, 874, 402], label: "가로"),
        Self.node(1, 4, [0, 0, 874.6, 402]),
      ],
      scale: 3,
      system: true
    )
    #expect(nodes.map(\.label) == [nil, "경계", "알림", "가로"])
  }

  @Test("깊이 1 창은 바로 앞 루트의 크기와 비교한다")
  func perRootComparison() throws {
    let nodes = try IOSLayoutConversion.nodes(
      from: [
        Self.node(0, 2, [0, 0, 100, 100]),
        Self.node(1, 4, [0, 0, 200, 200]),
        Self.node(0, 2, [0, 0, 300, 300]),
        Self.node(1, 4, [0, 0, 200, 200], label: "둘째 앱 창"),
      ],
      scale: 2,
      system: true
    )
    #expect(nodes.map(\.label) == [nil, nil, "둘째 앱 창"])
  }

  @Test("앱 스냅샷은 루트보다 큰 창도 빼지 않는다 (멀티태스킹 등 실측하지 않은 상태)")
  func appSnapshotKeepsWindows() throws {
    let nodes = try IOSLayoutConversion.nodes(
      from: [
        Self.node(0, 2, [0, 0, 400, 800]),
        Self.node(1, 4, [0, 0, 1200, 2400]),
        Self.node(2, 9, [10, 10, 50, 50], label: "버튼"),
      ],
      scale: 3,
      system: false
    )
    #expect(nodes.map(\.label) == [nil, nil, "버튼"])
  }

  @Test("scale 1 이면 루트와 같은 크기의 창을 남긴다")
  func scaleOneKeepsWindows() throws {
    let nodes = try IOSLayoutConversion.nodes(
      from: [Self.node(0, 2, [0, 0, 10, 10]), Self.node(1, 4, [0, 0, 10, 10])],
      scale: 1,
      system: true
    )
    #expect(nodes.count == 2)
  }

  @Test("텍스트는 value 먼저 없으면 title, 빈 문자열은 nil")
  func texts() throws {
    let nodes = try IOSLayoutConversion.nodes(
      from: [
        Self.node(0, identifier: "", label: "", title: "제목", value: "값"),
        Self.node(1, identifier: "id", label: "레이블", title: "제목", value: ""),
        Self.node(1, title: ""),
      ],
      scale: 2,
      system: false
    )
    #expect(nodes.map(\.text) == ["값", "제목", nil])
    #expect(nodes.map(\.identifier) == [nil, "id", nil])
    #expect(nodes.map(\.label) == [nil, "레이블", nil])
  }

  static let invalidCases: [([Node], Double)] = [
    ([node(1)], 3.0),
    ([node(0), node(2)], 3),
    ([node(0), node(-1)], 3),
    ([node(0, 1, [Double.nan, 0, 1, 1])], 3),
    ([node(0, 1, [0, 0, Double.infinity, 1])], 3),
    ([node(0)], 0),
    ([node(0)], Double.nan),
  ]

  @Test(
    "깊이 규칙 위반·유한하지 않은 수·잘못된 scale 은 unreadable",
    arguments: invalidCases
  )
  func invalid(nodes: [Node], scale: Double) {
    #expect(throws: ScreenLayoutError.unreadable) {
      try IOSLayoutConversion.nodes(from: nodes, scale: scale, system: false)
    }
  }

  @Test("깊이 512 까지 받고 넘으면 unreadable")
  func depthLimit() throws {
    let deep = (0 ... 512).map { Self.node($0) }
    #expect(try IOSLayoutConversion.nodes(from: deep, scale: 2, system: false).count == 513)
    #expect(throws: ScreenLayoutError.unreadable) {
      try IOSLayoutConversion.nodes(from: deep + [Self.node(513)], scale: 2, system: false)
    }
  }

  @Test("빈 노드 목록은 빈 결과")
  func empty() throws {
    #expect(try IOSLayoutConversion.nodes(from: [], scale: 3, system: false).isEmpty)
  }

  @Test("앱 식별자: 시스템 화면이면 SpringBoard, 하나면 그것, 여럿이면 쉼표로")
  func appIdentifier() {
    #expect(IOSLayoutConversion.appIdentifier(apps: ["com.apple.springboard"], system: true) == "com.apple.springboard")
    #expect(IOSLayoutConversion.appIdentifier(apps: ["a.b"], system: false) == "a.b")
    #expect(IOSLayoutConversion.appIdentifier(apps: ["a.b", "c.d"], system: false) == "a.b, c.d")
    #expect(IOSLayoutConversion.appIdentifier(apps: [], system: false) == nil)
  }
}

struct IOSLayoutReaderMappingTests {
  @Test(
    "Simulator 실패 매핑",
    arguments: [
      (SimulatorError.developerToolsUnavailable, ScreenLayoutError.xcodeUnavailable),
      (.deviceNotFound, .deviceNotFound),
      (.deviceNotBooted, .deviceNotBooted),
      (.commandFailed, .unreadable),
      (.unexpectedOutput, .unreadable),
    ]
  )
  func simulatorErrors(error: SimulatorError, expected: ScreenLayoutError) {
    #expect(IOSLayoutReader.mapSimulatorError(error) == expected)
  }

  @Test(
    "러너 실패 매핑",
    arguments: [
      (LayoutRunnerProtocol.RunnerFailure.notForeground, ScreenLayoutError.appNotInForeground),
      (.snapshotFailed, .unreadable),
      (.badRequest, .unreadable),
      (.unknownCommand, .unreadable),
    ]
  )
  func runnerFailures(failure: LayoutRunnerProtocol.RunnerFailure, expected: ScreenLayoutError) {
    #expect(IOSLayoutReader.mapRunnerFailure(failure) == expected)
    #expect(throws: expected) { try IOSLayoutReader.snapshot(from: .failure(failure)) }
  }

  @Test("xcodebuild 빌드 실패 매핑: 시작 못 함 → Xcode, 취소 → 취소, 시간 초과 → 준비 실패")
  func buildErrors() {
    #expect(LayoutRunnerBuildCache.mapBuildError(.launchFailed) == .xcodeUnavailable)
    #expect(LayoutRunnerBuildCache.mapBuildError(.cancelled) == .cancelled)
    #expect(LayoutRunnerBuildCache.mapBuildError(.timedOut) == .inspectorSetupFailed)
  }

  @Test("스냅샷 응답: 넘친 노드·quit 응답은 unreadable")
  func snapshotResponse() throws {
    let node = LayoutRunnerProtocol.Node(
      depth: 0, type: 2, x: 0, y: 0, width: 1, height: 1, identifier: nil, label: nil, title: nil, value: nil
    )
    let valid = LayoutRunnerProtocol.Snapshot(apps: ["a"], system: false, truncated: false, nodes: [node])
    #expect(try IOSLayoutReader.snapshot(from: .snapshot(valid)) == valid)
    let truncated = LayoutRunnerProtocol.Snapshot(apps: ["a"], system: false, truncated: true, nodes: [node])
    #expect(throws: ScreenLayoutError.unreadable) { try IOSLayoutReader.snapshot(from: .snapshot(truncated)) }
    let many = LayoutRunnerProtocol.Snapshot(
      apps: ["a"],
      system: false,
      truncated: false,
      nodes: Array(repeating: node, count: LayoutRunnerProtocol.maxNodes + 1)
    )
    #expect(throws: ScreenLayoutError.unreadable) { try IOSLayoutReader.snapshot(from: .snapshot(many)) }
    #expect(throws: ScreenLayoutError.unreadable) { try IOSLayoutReader.snapshot(from: .quit) }
  }

  @Test("PNG 크기: IHDR 의 너비·높이, PNG 아님·짧음·0 은 nil")
  func pngSize() {
    #expect(IOSLayoutReader.pngSize(RunnerHarness.png) == LayoutSize(width: 1206, height: 2622))
    #expect(IOSLayoutReader.pngSize(Data(RunnerHarness.png.prefix(23))) == nil)
    var notPNG = RunnerHarness.png
    notPNG[1] = 0
    #expect(IOSLayoutReader.pngSize(notPNG) == nil)
    var zero = RunnerHarness.png
    zero.replaceSubrange(16 ..< 20, with: [0, 0, 0, 0])
    #expect(IOSLayoutReader.pngSize(zero) == nil)
  }
}
