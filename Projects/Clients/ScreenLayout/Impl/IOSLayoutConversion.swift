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
  /// 시스템 화면(`system`, SpringBoard)이면 루트 바로 아래(깊이 1)에서 그 루트 안에 들어가지 않는 창(가로·세로를 바꿔도 폭이나 높이가 0.5 넘게 크다)은 하위 전체와 함께 뺀다:
  /// 스크린샷에 없는 화면의 창이다 (실측 Xcode 27.2: SpringBoard 가 px 로 보고한 빈 창(루트 × scale), 화면이 둘인 iPhone Duo 의
  /// SpringBoard 에 섞인 안쪽 화면의 창(pt 669x951·px 2007x2853. 빼지 않으면 바깥 화면 466x678 스크린샷 위에 어긋나 그려진다)).
  /// 가로·세로를 바꾼 크기를 함께 보는 것은 가로로 돌린 iPad 의 SpringBoard 가 창을 세로 크기(루트 1210x834, 창 834x1210)로
  /// 보고하기 때문이다(그 하위 좌표도 세로 기준이라 테두리가 어긋나지만 이 규칙의 범위 밖이다). 앱 스냅샷에는 적용하지 않는다: 이런 창이
  /// 관찰되지 않았고(Duo·iPhone·iPad 가로에서 창이 루트와 같은 크기), iPad 멀티태스킹처럼 실측하지 않은 상태에서 앱 창을 통째로 빼지 않게.
  /// 뺀 뒤 id 를 다시 매겨 `nodes[i].id == i` 다.
  static func nodes(
    from runnerNodes: [LayoutRunnerProtocol.Node],
    scale: Double,
    system: Bool
  ) throws(ScreenLayoutError) -> [LayoutNode] {
    guard scale.isFinite, scale > 0 else { throw .unreadable }
    try self.validate(runnerNodes)
    let kept = system ? self.removingOversizedWindows(runnerNodes) : runnerNodes
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
