import AndroidEmulatorInterface
import Core
import Foundation

/// `uiautomator dump` XML(`<hierarchy rotation="N"><node …>…</hierarchy>`)을 노드 목록으로 바꾼다 (순수).
/// 덤프는 기기 안 앱이 정한 문자열을 담으므로 신뢰하지 않는 입력으로 다룬다: 바이트·노드 수·깊이에 상한을 두고 넘으면 거절하며,
/// 외부 엔티티는 풀지 않는다(`XMLParser` 기본값 그대로).
enum UIAutomatorDumpParser {
  struct Parsed: Equatable {
    /// 전위 순서 (`nodes[i].id == i`).
    let nodes: [LayoutNode]
    /// 첫 노드의 package. 비었으면 nil.
    let appIdentifier: String?
    /// 노드가 1개 이상이고 모두 package 가 `com.android.systemui` (잠금 화면·알림 창).
    let isSystemScreen: Bool
  }

  static let maxBytes = 8 * 1024 * 1024
  static let maxNodes = 20000
  /// 노드 깊이(루트 노드 0)의 상한.
  static let maxDepth = 512
  static let systemUIPackage = "com.android.systemui"

  /// 루트가 `<hierarchy>` 가 아니거나, XML 이 깨졌거나, 상한을 넘으면 `.layoutUnreadable`. 노드 0개는 성공(빈 목록).
  /// bounds 가 없거나 형식(`[l,t][r,b]`, 숫자는 부호 포함 9자리 이하)이 틀린 노드는 크기 0 사각형으로 남긴다(숨김, 깊이는 지킨다).
  static func parse(_ data: Data) throws(AndroidEmulatorError) -> Parsed {
    guard data.count <= self.maxBytes else { throw .layoutUnreadable }
    let parser = XMLParser(data: data)
    let delegate = Delegate()
    parser.delegate = delegate
    let parsed = parser.parse()
    guard parsed, delegate.sawRoot, !delegate.rejected else { throw .layoutUnreadable }
    let nodes = delegate.nodes
    let packages = delegate.packages
    return Parsed(
      nodes: nodes,
      appIdentifier: packages.first.flatMap(\.self),
      isSystemScreen: !packages.isEmpty && packages.allSatisfy { $0 == self.systemUIPackage }
    )
  }

  /// `[l,t][r,b]` → px 사각형. 네 값을 Double 로 바꾼 뒤 빼므로 넘치지 않는다. 뒤집힌 bounds 는 음수 너비·높이 그대로 둔다
  /// (Core 가 숨긴다). 형식이 틀리면 nil.
  static func frame(_ bounds: String) -> LayoutRect? {
    let pattern = /\[(-?\d{1,9}),(-?\d{1,9})\]\[(-?\d{1,9}),(-?\d{1,9})\]/
    guard let match = try? pattern.wholeMatch(in: bounds),
          let left = Double(match.1), let top = Double(match.2),
          let right = Double(match.3), let bottom = Double(match.4)
    else { return nil }
    return LayoutRect(x: left, y: top, width: right - left, height: bottom - top)
  }

  static func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
  }
}

// MARK: - XMLParser delegate

/// 한 번의 `parse()` 동안만 쓰는 상태 (Sendable 이 아니다).
private final class Delegate: NSObject, XMLParserDelegate {
  private(set) var sawRoot = false
  private(set) var rejected = false
  private(set) var nodes: [LayoutNode] = []
  /// `nodes` 와 같은 순서의 package (빈 값은 nil).
  private(set) var packages: [String?] = []
  /// 열린 요소들: `<node>` 면 그 번호, 그 밖의 요소(`<hierarchy>` 포함)는 nil.
  private var stack: [Int?] = []

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI _: String?,
    qualifiedName _: String?,
    attributes: [String: String] = [:]
  ) {
    if self.stack.isEmpty {
      guard elementName == "hierarchy" else {
        self.reject(parser)
        return
      }
      self.sawRoot = true
      self.stack.append(nil)
      return
    }
    guard elementName == "node" else {
      self.stack.append(nil)
      return
    }
    let parentID = self.stack.last { $0 != nil } ?? nil
    let depth = self.stack.count { $0 != nil }
    guard depth <= UIAutomatorDumpParser.maxDepth, self.nodes.count < UIAutomatorDumpParser.maxNodes else {
      self.reject(parser)
      return
    }
    let id = self.nodes.count
    let frame = attributes["bounds"].flatMap(UIAutomatorDumpParser.frame) ?? LayoutRect(x: 0, y: 0, width: 0, height: 0)
    self.nodes.append(LayoutNode(
      id: id,
      depth: depth,
      parentID: parentID,
      frame: frame,
      type: attributes["class"] ?? "",
      identifier: UIAutomatorDumpParser.nonEmpty(attributes["resource-id"]),
      text: UIAutomatorDumpParser.nonEmpty(attributes["text"]),
      label: UIAutomatorDumpParser.nonEmpty(attributes["content-desc"])
    ))
    self.packages.append(UIAutomatorDumpParser.nonEmpty(attributes["package"]))
    self.stack.append(id)
  }

  func parser(
    _: XMLParser,
    didEndElement _: String,
    namespaceURI _: String?,
    qualifiedName _: String?
  ) {
    if !self.stack.isEmpty {
      self.stack.removeLast()
    }
  }

  private func reject(_ parser: XMLParser) {
    self.rejected = true
    parser.abortParsing()
  }
}
