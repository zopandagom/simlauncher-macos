import Foundation

/// 저장소 XML 에서 package.xml 에 다시 쓸 원문 조각(`AndroidLocalPackageSource`)을 잡는 데 쓰는 초안·`xmlns` 범위 도우미.
/// 잡는 상태는 `AndroidRepositoryReader.swift` 의 XMLParser delegate 가 갖는다.
extension AndroidRepositoryReader {
  /// 원문 조각 초안. 잡는 세 요소의 로컬 이름.
  struct SourceDraft {
    static let kinds: Set<String> = ["type-details", "revision", "dependencies"]

    var invalid = false
    var seen: Set<String> = []
    var typeNamespace: String?
    var typeName: String?
    var typeDetails: [AndroidXMLNode]?
    var revision: AndroidXMLNode?
    var dependencies: AndroidXMLNode?

    /// 무효가 아니고 type 이 풀렸고 type-details·revision 을 잡았을 때만.
    var source: AndroidLocalPackageSource? {
      guard
        !self.invalid,
        let typeNamespace = self.typeNamespace,
        let typeName = self.typeName,
        let typeDetails = self.typeDetails,
        let revision = self.revision
      else {
        return nil
      }
      return AndroidLocalPackageSource(
        typeNamespace: typeNamespace,
        typeName: typeName,
        typeDetails: typeDetails,
        revision: revision,
        dependencies: self.dependencies
      )
    }
  }

  /// 잡는 중인 요소 하나.
  struct CaptureFrame {
    let name: String
    let attributes: [String: String]
    var children: [AndroidXMLNode] = []

    var node: AndroidXMLNode {
      .element(name: self.name, attributes: self.attributes, children: self.children)
    }

    /// 이어진 글자는 마지막 글자 마디에 붙인다 (XMLParser 는 엔티티 앞뒤에서 글자를 나눠 준다).
    mutating func append(text: String) {
      if case let .text(previous) = self.children.last {
        self.children[self.children.count - 1] = .text(previous + text)
      } else {
        self.children.append(.text(text))
      }
    }
  }

  static let schemaInstance = "http://www.w3.org/2001/XMLSchema-instance"

  /// 부모 범위에 이 요소의 `xmlns`(키 "")·`xmlns:p`(키 `p`) 선언을 덮는다.
  static func scope(adding attributes: [String: String], to parent: [String: String]) -> [String: String] {
    var scope = parent
    for (key, value) in attributes {
      if key == "xmlns" {
        scope[""] = value
      } else if key.hasPrefix("xmlns:") {
        scope[String(key.dropFirst("xmlns:".count))] = value
      }
    }
    return scope
  }

  /// 옮겨 쓸 수 없는 이름: 접두가 있다.
  static func isPrefixed(_ name: String) -> Bool {
    name.contains(":")
  }

  /// 옮겨 쓸 수 없는 속성: 이름에 접두가 있거나 `xmlns` 로 시작한다.
  static func hasForeignAttribute(_ attributes: [String: String]) -> Bool {
    attributes.keys.contains { $0.contains(":") || $0.hasPrefix("xmlns") }
  }

  /// `p:type`(p 가 XMLSchema-instance) 속성 하나의 값 `q:name` 을 (q 의 URI, name) 으로. 없거나 모양이 다르면 nil.
  static func schemaType(
    _ attributes: [String: String],
    scope: [String: String]
  ) -> (namespace: String, name: String)? {
    let types = attributes.filter { key, _ in
      let parts = key.split(separator: ":", omittingEmptySubsequences: false)
      return parts.count == 2 && parts[1] == "type" && scope[String(parts[0])] == Self.schemaInstance
    }
    guard types.count == 1, let value = types.first?.value else {
      return nil
    }
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty, let namespace = scope[String(parts[0])] else {
      return nil
    }
    return (namespace, String(parts[1]))
  }
}
