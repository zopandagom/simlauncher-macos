import Core
import Foundation

public extension LayoutSnapshot {
  /// 1×1 투명 PNG (테스트용 자리 채우기. 크기는 `pixelSize` 와 맞지 않는다).
  static let placeholderPNG = Data([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00,
    0x00, 0x05, 0x00, 0x01, 0x7A, 0x5E, 0xAB, 0x3F, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
    0xAE, 0x42, 0x60, 0x82,
  ])

  /// 1080×2400 px 휴대전화 화면 모양의 작은 계층 (밀도 420 → 2.625 px/dp).
  /// 0 루트 FrameLayout(전체) ─ 1 툴바(0,0,1080,168) ─ 2 "Navigate up" 버튼(85,105,63,63)
  ///                         └ 3 목록(0,168,1080,2232) ─ 4 항목 "Wi-Fi"(0,168,1080,200)
  ///                                                  └ 5 크기 0 노드(숨김)
  static func sample(
    deviceName: String = "Pixel 9",
    capturedAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
    screenshotPNG: Data = Self.placeholderPNG,
    pixelSize: LayoutSize = LayoutSize(width: 1080, height: 2400),
    unit: LayoutUnit = .dp,
    pixelsPerUnit: Double? = 2.625,
    nodes: [LayoutNode] = Self.sampleNodes,
    appIdentifier: String? = "com.example.app",
    isSystemScreen: Bool = false
  ) -> LayoutSnapshot {
    LayoutSnapshot(
      deviceName: deviceName,
      capturedAt: capturedAt,
      screenshotPNG: screenshotPNG,
      pixelSize: pixelSize,
      unit: unit,
      pixelsPerUnit: pixelsPerUnit,
      nodes: nodes,
      appIdentifier: appIdentifier,
      isSystemScreen: isSystemScreen
    )
  }

  /// `sample()` 의 노드.
  static let sampleNodes: [LayoutNode] = [
    LayoutNode(
      id: 0,
      depth: 0,
      parentID: nil,
      frame: LayoutRect(x: 0, y: 0, width: 1080, height: 2400),
      type: "android.widget.FrameLayout"
    ),
    LayoutNode(
      id: 1,
      depth: 1,
      parentID: 0,
      frame: LayoutRect(x: 0, y: 0, width: 1080, height: 168),
      type: "android.view.ViewGroup",
      identifier: "com.example.app:id/toolbar"
    ),
    LayoutNode(
      id: 2,
      depth: 2,
      parentID: 1,
      frame: LayoutRect(x: 85, y: 105, width: 63, height: 63),
      type: "android.widget.ImageButton",
      label: "Navigate up"
    ),
    LayoutNode(
      id: 3,
      depth: 1,
      parentID: 0,
      frame: LayoutRect(x: 0, y: 168, width: 1080, height: 2232),
      type: "androidx.recyclerview.widget.RecyclerView",
      identifier: "com.example.app:id/list"
    ),
    LayoutNode(
      id: 4,
      depth: 2,
      parentID: 3,
      frame: LayoutRect(x: 0, y: 168, width: 1080, height: 200),
      type: "android.widget.TextView",
      text: "Wi-Fi"
    ),
    LayoutNode(
      id: 5,
      depth: 2,
      parentID: 3,
      frame: LayoutRect(x: 0, y: 368, width: 0, height: 0),
      type: "android.view.View"
    ),
  ]
}
