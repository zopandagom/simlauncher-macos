import Core
import ScreenLayoutInterface

/// 러너 응답 노드(pt) → `LayoutNode`(px). 순수.
/// px = pt × scale (scale = ready.json 의 `UIScreen.main.scale`). 노드 id 는 응답 순서(전위)대로 0…, 부모는 깊이 스택으로 정한다.
enum IOSLayoutConversion {
  /// 깊이 상한 (규칙 위반으로 거절).
  static let maxDepth = 512

  /// 시스템 화면일 때의 앱 식별자.
  static let springBoard = "com.apple.springboard"

  /// 규칙 위반(첫 깊이 ≠ 0, 깊이가 앞보다 2 이상 큼, 음수·512 초과, 수가 유한하지 않음, scale 이 유한한 양수 아님)이면 `.unreadable`.
  /// 시스템 화면(`system`, SpringBoard)이면 두 가지를 더 한다 (앱 스냅샷에는 하지 않는다: 앱 노드는 화면 좌표로 온다
  /// (iPad 가로·거꾸로 세로의 설정·Spotlight 실측. 윈도우형 앱·스테이지 매니저의 창 안 좌표는 러너가 카드 위치만큼 옮겨 보낸다),
  /// 그리고 앱 창을 통째로 빼지 않는다).
  /// 1. 루트 바로 아래(깊이 1)에서 그 루트 안에 들어가지 않는 창(가로·세로를 바꿔도 폭이나 높이가 0.5 넘게 크다)은 하위 전체와 함께 뺀다:
  ///    스크린샷에 없는 화면의 창이다 (실측 Xcode 27.2: SpringBoard 가 px 로 보고한 빈 창(루트 × scale), 화면이 둘인 iPhone Duo 의
  ///    SpringBoard 에 섞인 안쪽 화면의 창(pt 669x951·px 2007x2853. 빼지 않으면 바깥 화면 466x678 스크린샷 위에 어긋나 그려진다)).
  ///    가로·세로를 바꾼 크기를 함께 보는 것은 가로로 돌린 iPad 의 창이 세로 크기(루트 1210x834, 창 834x1210)로 오기 때문이다.
  /// 2. 화면을 돌린 iPad 에서 SpringBoard 는 루트 밖의 모든 노드를 기기의 세로 좌표(돌리기 전)로 보고한다 (실측 Xcode 27.2·iOS 27.0,
  ///    iPad Pro 11·iPad mini 의 홈·잠금·알림 창·앱 보관함·앱 전환기. 앱 전환기에서는 루트도 세로 크기로 온다). 상태 막대가 보이는 쪽으로
  ///    화면 방향을 정해(`rotation(of:root:)`) 화면 좌표로 돌리고, 루트는 돌린 화면 크기로 둔다. 기기 방향(`XCUIDevice.orientation`)을
  ///    쓰지 않는 것은 iPhone 홈 화면은 기기를 돌려도 세로로 남기 때문이다(상태 막대도 위에 남아 돌리지 않는다).
  /// 뺀 뒤 id 를 다시 매겨 `nodes[i].id == i` 다.
  static func nodes(
    from runnerNodes: [LayoutRunnerProtocol.Node],
    scale: Double,
    system: Bool
  ) throws(ScreenLayoutError) -> [LayoutNode] {
    guard scale.isFinite, scale > 0 else { throw .unreadable }
    try self.validate(runnerNodes)
    let kept = system ? self.rotatedToScreen(self.removingOversizedWindows(runnerNodes)) : runnerNodes
    var result: [LayoutNode] = []
    result.reserveCapacity(kept.count)
    var stack: [Int] = []
    for node in kept {
      stack.removeLast(stack.count - node.depth)
      let id = result.count
      result.append(
        LayoutNode(
          id: id,
          depth: node.depth,
          parentID: stack.last,
          frame: LayoutRect(
            x: node.x * scale,
            y: node.y * scale,
            width: node.width * scale,
            height: node.height * scale
          ),
          type: self.typeName(node.type),
          identifier: self.nonEmpty(node.identifier),
          text: self.nonEmpty(node.value) ?? self.nonEmpty(node.title),
          label: self.nonEmpty(node.label)
        )
      )
      stack.append(id)
    }
    return result
  }

  /// 툴바의 앱 식별자: 시스템 화면이면 SpringBoard, 앱이 하나면 그것, 여럿이면 `", "` 로 이은 값, 없으면 nil.
  static func appIdentifier(apps: [String], system: Bool) -> String? {
    if system {
      return self.springBoard
    }
    return apps.isEmpty ? nil : apps.joined(separator: ", ")
  }

  private static func validate(_ nodes: [LayoutRunnerProtocol.Node]) throws(ScreenLayoutError) {
    var previous: Int?
    for node in nodes {
      let numbers = [node.x, node.y, node.width, node.height]
      guard numbers.allSatisfy(\.isFinite), node.depth >= 0, node.depth <= self.maxDepth else { throw .unreadable }
      if let previous {
        guard node.depth <= previous + 1 else { throw .unreadable }
      } else {
        guard node.depth == 0 else { throw .unreadable }
      }
      previous = node.depth
    }
  }

  /// 깊이 1 노드 중 그 루트 안에 (가로·세로를 바꿔서도) 들어가지 않는 것을 하위와 함께 뺀다.
  private static func removingOversizedWindows(
    _ nodes: [LayoutRunnerProtocol.Node]
  ) -> [LayoutRunnerProtocol.Node] {
    var kept: [LayoutRunnerProtocol.Node] = []
    kept.reserveCapacity(nodes.count)
    var root: LayoutRunnerProtocol.Node?
    var skippingBelow: Int?
    for node in nodes {
      if let depth = skippingBelow {
        if node.depth > depth {
          continue
        }
        skippingBelow = nil
      }
      if node.depth == 0 {
        root = node
      } else if node.depth == 1, let root, self.isOversized(node, root: root) {
        skippingBelow = node.depth
        continue
      }
      kept.append(node)
    }
    return kept
  }

  /// SpringBoard 의 세로 좌표 → 화면 좌표. 루트마다 그 하위의 상태 막대로 방향을 정한다.
  private static func rotatedToScreen(_ nodes: [LayoutRunnerProtocol.Node]) -> [LayoutRunnerProtocol.Node] {
    var result: [LayoutRunnerProtocol.Node] = []
    result.reserveCapacity(nodes.count)
    var start = 0
    while start < nodes.count {
      var end = start + 1
      while end < nodes.count, nodes[end].depth > 0 {
        end += 1
      }
      let tree = nodes[start ..< end]
      let root = tree[tree.startIndex]
      let rotation = self.rotation(of: tree.dropFirst(), root: root)
      let size = PortraitSize(root)
      for (offset, node) in tree.enumerated() {
        let rotated = offset == 0
          ? self.rotatedRoot(root, size: size, rotation: rotation)
          : rotation.apply(node, size: size)
        result.append(rotated)
      }
      start = end
    }
    return result
  }

  /// 기기의 세로 크기 (짧은 변이 폭). 루트가 가로 크기로 와도 같다.
  struct PortraitSize: Equatable {
    let width: Double
    let height: Double

    init(_ root: LayoutRunnerProtocol.Node) {
      self.width = min(root.width, root.height)
      self.height = max(root.width, root.height)
    }
  }

  /// SpringBoard 의 화면 방향 (세로 좌표 → 화면 좌표 변환). 이름은 기기 방향(`UIDeviceOrientation`)을 따른다.
  enum ScreenRotation: Equatable {
    /// 세로. 그대로 둔다 (상태 막대가 위, 또는 상태 막대를 알아볼 수 없음).
    case portrait
    /// 거꾸로 세로: 상태 막대가 세로 좌표의 아래. 180° 돌린다.
    case upsideDown
    /// 가로 좌(홈 표시가 오른쪽): 상태 막대가 세로 좌표의 오른쪽 끝. 화면 x = y, 화면 y = W − x − w.
    case landscapeLeft
    /// 가로 우: 상태 막대가 세로 좌표의 왼쪽 끝. 화면 x = H − y − h, 화면 y = x.
    case landscapeRight

    func apply(_ node: LayoutRunnerProtocol.Node, size: PortraitSize) -> LayoutRunnerProtocol.Node {
      switch self {
      case .portrait:
        node
      case .upsideDown:
        node.moved(
          x: size.width - node.x - node.width,
          y: size.height - node.y - node.height,
          width: node.width,
          height: node.height
        )
      case .landscapeLeft:
        node.moved(x: node.y, y: size.width - node.x - node.width, width: node.height, height: node.width)
      case .landscapeRight:
        node.moved(x: size.height - node.y - node.height, y: node.x, width: node.height, height: node.width)
      }
    }
  }

  /// `XCUIElement.ElementType.statusBar` 원시 값.
  static let statusBarType = 25

  /// 하위 노드 중 앞에서부터 처음 나오는 띠 모양 상태 막대(짧은 변이 세로 크기 폭의 ¼ 미만이고, 긴 변이 세로 크기의 한 변과 같고(0.5 안),
  /// 그 변에 붙어 있다)로 방향을 정한다. 없으면 `.portrait` (iPhone Duo 의 상태 막대는 화면 크기라 여기에 들지 않는다).
  static func rotation(
    of descendants: some Sequence<LayoutRunnerProtocol.Node>,
    root: LayoutRunnerProtocol.Node
  ) -> ScreenRotation {
    let size = PortraitSize(root)
    let thin = size.width / 4
    let near = { (value: Double, target: Double) in abs(value - target) <= 0.5 }
    for node in descendants where node.type == self.statusBarType {
      if near(node.width, size.width), node.height < thin {
        if near(node.y, 0) {
          return .portrait
        }
        if near(node.y + node.height, size.height) {
          return .upsideDown
        }
      } else if near(node.height, size.height), node.width < thin {
        if near(node.x, 0) {
          return .landscapeRight
        }
        if near(node.x + node.width, size.width) {
          return .landscapeLeft
        }
      }
    }
    return .portrait
  }

  private static func rotatedRoot(
    _ root: LayoutRunnerProtocol.Node,
    size: PortraitSize,
    rotation: ScreenRotation
  ) -> LayoutRunnerProtocol.Node {
    switch rotation {
    case .portrait:
      root
    case .upsideDown:
      root.moved(x: 0, y: 0, width: size.width, height: size.height)
    case .landscapeLeft, .landscapeRight:
      root.moved(x: 0, y: 0, width: size.height, height: size.width)
    }
  }

  private static func isOversized(_ node: LayoutRunnerProtocol.Node, root: LayoutRunnerProtocol.Node) -> Bool {
    !self.fits(node, width: root.width, height: root.height) && !self.fits(node, width: root.height, height: root.width)
  }

  private static func fits(_ node: LayoutRunnerProtocol.Node, width: Double, height: Double) -> Bool {
    node.width <= width + 0.5 && node.height <= height + 0.5
  }

  private static func nonEmpty(_ text: String?) -> String? {
    guard let text, !text.isEmpty else { return nil }
    return text
  }

  /// `XCUIElement.ElementType` 원시 값 → 이름 (SDK 헤더 `XCUIElementTypes.h` 의 값). 표 밖이면 `ElementType(<값>)`.
  static func typeName(_ raw: Int) -> String {
    guard self.elementTypeNames.indices.contains(raw) else { return "ElementType(\(raw))" }
    return self.elementTypeNames[raw]
  }

  /// 0 Any … 82 StatusItem (원시 값 = 인덱스).
  static let elementTypeNames = [
    "Any", "Other", "Application", "Group", "Window", "Sheet", "Drawer", "Alert", "Dialog", "Button",
    "RadioButton", "RadioGroup", "CheckBox", "DisclosureTriangle", "PopUpButton", "ComboBox", "MenuButton",
    "ToolbarButton", "Popover", "Keyboard", "Key", "NavigationBar", "TabBar", "TabGroup", "Toolbar", "StatusBar",
    "Table", "TableRow", "TableColumn", "Outline", "OutlineRow", "Browser", "CollectionView", "Slider",
    "PageIndicator", "ProgressIndicator", "ActivityIndicator", "SegmentedControl", "Picker", "PickerWheel",
    "Switch", "Toggle", "Link", "Image", "Icon", "SearchField", "ScrollView", "ScrollBar", "StaticText",
    "TextField", "SecureTextField", "DatePicker", "TextView", "Menu", "MenuItem", "MenuBar", "MenuBarItem", "Map",
    "WebView", "IncrementArrow", "DecrementArrow", "Timeline", "RatingIndicator", "ValueIndicator", "SplitGroup",
    "Splitter", "RelevanceIndicator", "ColorWell", "HelpTag", "Matte", "DockItem", "Ruler", "RulerMarker", "Grid",
    "LevelIndicator", "Cell", "LayoutArea", "LayoutItem", "Handle", "Stepper", "Tab", "TouchBar", "StatusItem",
  ]
}

private extension LayoutRunnerProtocol.Node {
  /// 프레임만 바꾼 노드.
  func moved(x: Double, y: Double, width: Double, height: Double) -> Self {
    Self(
      depth: self.depth,
      type: self.type,
      x: x,
      y: y,
      width: width,
      height: height,
      identifier: self.identifier,
      label: self.label,
      title: self.title,
      value: self.value
    )
  }
}
