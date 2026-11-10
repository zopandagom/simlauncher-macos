import Foundation

/// 스크린샷 픽셀(px) 좌표의 사각형. 원점은 화면 왼쪽 위다. 덤프 그대로라 너비·높이가 0 이거나 음수(뒤집힌 bounds)일 수 있다.
public struct LayoutRect: Hashable, Sendable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  /// 반열림 [x, x+w)×[y, y+h) 안이면 true (오른쪽·아래 가장자리는 이웃 노드 몫이다).
  public func contains(_ point: LayoutPoint) -> Bool {
    point.x >= self.x && point.x < self.x + self.width && point.y >= self.y && point.y < self.y + self.height
  }
}

/// 스크린샷 픽셀(px) 좌표의 점.
public struct LayoutPoint: Hashable, Sendable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// 스크린샷 PNG 의 픽셀 크기 (화면 크기의 출처, 둘 다 > 0).
public struct LayoutSize: Hashable, Sendable {
  public let width: Int
  public let height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }
}

/// 뷰 계층의 노드 하나 (Android `<node>`, iOS 접근성 요소).
public struct LayoutNode: Hashable, Sendable, Identifiable {
  /// 문서 순서(전위) 번호 0… (스냅샷의 `nodes` 안 위치와 같다).
  public let id: Int
  /// 루트 0.
  public let depth: Int
  public let parentID: Int?
  /// px.
  public let frame: LayoutRect
  /// Android class, iOS elementType 이름.
  public let type: String
  /// Android resource-id, iOS accessibilityIdentifier. 빈 값은 nil.
  public let identifier: String?
  /// Android text, iOS value·title. 빈 값은 nil.
  public let text: String?
  /// Android content-desc, iOS label. 빈 값은 nil.
  public let label: String?

  public init(
    id: Int,
    depth: Int,
    parentID: Int?,
    frame: LayoutRect,
    type: String,
    identifier: String? = nil,
    text: String? = nil,
    label: String? = nil
  ) {
    self.id = id
    self.depth = depth
    self.parentID = parentID
    self.frame = frame
    self.type = type
    self.identifier = identifier
    self.text = text
    self.label = label
  }
}

/// 화면에 보이는 크기의 단위. Android dp, iOS pt.
public enum LayoutUnit: String, Hashable, Sendable {
  case dp
  case pt
}

/// 한 번 읽은 기기 화면: 스크린샷과 뷰 계층(px 좌표). 메모리에만 둔다.
public struct LayoutSnapshot: Hashable, Sendable {
  public let deviceName: String
  public let capturedAt: Date
  public let screenshotPNG: Data
  /// PNG 의 픽셀 크기 (화면 크기의 출처).
  public let pixelSize: LayoutSize
  /// Android `.dp`, iOS `.pt`.
  public let unit: LayoutUnit
  /// 단위 하나의 px 수 (Android density/160, iOS scale). 읽지 못하면 nil → px 만 보인다.
  public let pixelsPerUnit: Double?
  /// 숨길 노드를 포함한 원본, 전위 순서 (`nodes[i].id == i`).
  public let nodes: [LayoutNode]
  /// 맨 위 노드의 package (iOS bundle ID). 모르면 nil.
  public let appIdentifier: String?
  /// 잠금 화면·알림 창 같은 시스템 화면 (Android: 모든 노드 package 가 `com.android.systemui`).
  public let isSystemScreen: Bool
  /// 테두리·hit-test 대상: 너비·높이 > 0 이고 화면 사각형 [0,0,W,H] 와 겹치는 노드, 전위 순서
  /// (크기 0·뒤집힌 bounds·화면 밖 노드는 숨긴다).
  public let visibleNodes: [LayoutNode]

  public init(
    deviceName: String,
    capturedAt: Date,
    screenshotPNG: Data,
    pixelSize: LayoutSize,
    unit: LayoutUnit,
    pixelsPerUnit: Double?,
    nodes: [LayoutNode],
    appIdentifier: String?,
    isSystemScreen: Bool
  ) {
    self.deviceName = deviceName
    self.capturedAt = capturedAt
    self.screenshotPNG = screenshotPNG
    self.pixelSize = pixelSize
    self.unit = unit
    self.pixelsPerUnit = pixelsPerUnit
    self.nodes = nodes
    self.appIdentifier = appIdentifier
    self.isSystemScreen = isSystemScreen
    self.visibleNodes = nodes.filter { Self.isVisible($0.frame, in: pixelSize) }
  }

  /// 번호의 노드. 없으면 nil.
  public func node(_ id: LayoutNode.ID) -> LayoutNode? {
    if self.nodes.indices.contains(id), self.nodes[id].id == id {
      return self.nodes[id]
    }
    return self.nodes.first { $0.id == id }
  }

  /// 점을 포함하는(반열림) 보이는 노드의 번호, 바깥→안쪽: 넓이 내림차순 → depth 오름차순 → id 오름차순.
  /// 마지막 원소가 기본으로 고를 "가장 안쪽(가장 작은)" 노드다. 점이 화면 [0,W)×[0,H) 밖이면 빈 배열.
  public func nodes(at point: LayoutPoint) -> [LayoutNode.ID] {
    let screen = LayoutRect(
      x: 0,
      y: 0,
      width: Double(self.pixelSize.width),
      height: Double(self.pixelSize.height)
    )
    guard screen.contains(point) else { return [] }
    return self.visibleNodes
      .filter { $0.frame.contains(point) }
      .sorted { lhs, rhs in
        let lhsArea = lhs.frame.width * lhs.frame.height
        let rhsArea = rhs.frame.width * rhs.frame.height
        if lhsArea != rhsArea {
          return lhsArea > rhsArea
        }
        if lhs.depth != rhs.depth {
          return lhs.depth < rhs.depth
        }
        return lhs.id < rhs.id
      }
      .map(\.id)
  }

  private static func isVisible(_ frame: LayoutRect, in size: LayoutSize) -> Bool {
    frame.width > 0 && frame.height > 0
      && frame.x < Double(size.width) && frame.x + frame.width > 0
      && frame.y < Double(size.height) && frame.y + frame.height > 0
  }
}
