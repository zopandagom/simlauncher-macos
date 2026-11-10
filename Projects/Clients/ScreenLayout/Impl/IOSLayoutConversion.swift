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
  /// 루트 바로 아래(깊이 1)에서 px 로 보고된 창(크기가 루트 × scale 과 0.5 안으로 같다, scale > 1)은 하위 전체와 함께 뺀다
  /// (실측: SpringBoard 의 빈 창 3개). 뺀 뒤 id 를 다시 매겨 `nodes[i].id == i` 다.
  static func nodes(
    from runnerNodes: [LayoutRunnerProtocol.Node],
    scale: Double
  ) throws(ScreenLayoutError) -> [LayoutNode] {
    guard scale.isFinite, scale > 0 else { throw .unreadable }
    try self.validate(runnerNodes)
    let kept = self.removingPixelWindows(runnerNodes, scale: scale)
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

  /// 깊이 1 노드 중 크기가 그 루트 × scale 과 같은(±0.5) 것을 하위와 함께 뺀다. scale ≤ 1 이면 구분할 수 없어 그대로 둔다.
  private static func removingPixelWindows(
    _ nodes: [LayoutRunnerProtocol.Node],
    scale: Double
  ) -> [LayoutRunnerProtocol.Node] {
    guard scale > 1 else { return nodes }
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
      } else if node.depth == 1, let root, self.isPixelWindow(node, root: root, scale: scale) {
        skippingBelow = node.depth
        continue
      }
      kept.append(node)
    }
    return kept
  }

  private static func isPixelWindow(
    _ node: LayoutRunnerProtocol.Node,
    root: LayoutRunnerProtocol.Node,
    scale: Double
  ) -> Bool {
    abs(node.width - root.width * scale) <= 0.5 && abs(node.height - root.height * scale) <= 0.5
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
