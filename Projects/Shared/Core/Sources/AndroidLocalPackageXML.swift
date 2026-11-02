import Foundation

/// Android Studio(sdklib)가 설치된 패키지로 읽는 `package.xml` 내용. 저장소 XML 의 같은 remotePackage 로 만든다.
/// 형식 (줄바꿈·들여쓰기 없이 한 줄, 끝 줄바꿈 없음, UTF-8):
/// ```
/// <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
/// <ns2:repository xmlns:ns2="…/repository/android/common/02" xmlns:ns3="(type 네임스페이스)">
/// <license id="…" type="text">원문</license>
/// <localPackage path="…" obsolete="false">
/// <type-details xmlns:xsi="…/XMLSchema-instance" xsi:type="ns3:(type 이름)">(자식)</type-details>
/// <revision>…</revision> <display-name>…</display-name> <uses-license ref="…"/> <dependencies>…</dependencies>
/// </localPackage></ns2:repository>
/// ```
/// - 요소: 속성은 이름 순, 자식이 없으면 `<name/>`. 공백(` `·`\t`·`\n`·`\r`)만 있는 글자 마디는 버리고, 나머지 글자는 다듬지 않는다.
/// - 접두 `ns2`·`ns3` 은 고정, license `type` 은 스키마 고정값 `text`, `obsolete` 는 항상 `false` (선택이 obsolete 를 고르지 않는다).
public enum AndroidLocalPackageXML {
  static let commonNamespace = "http://schemas.android.com/repository/android/common/02"
  static let schemaInstanceNamespace = "http://www.w3.org/2001/XMLSchema-instance"

  /// 원문 조각이 없거나 `package.licenseID != license.id` 면 nil.
  public static func render(_ package: AndroidRemotePackage, license: AndroidLicense) -> Data? {
    guard let source = package.localPackageSource, package.licenseID == license.id else {
      return nil
    }
    let typeDetails = Self.children(source.typeDetails)
    var out = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
    out += "<ns2:repository xmlns:ns2=\"\(Self.attribute(Self.commonNamespace))\""
    out += " xmlns:ns3=\"\(Self.attribute(source.typeNamespace))\">"
    out += "<license id=\"\(Self.attribute(license.id))\" type=\"text\">\(Self.text(license.text))</license>"
    out += "<localPackage path=\"\(Self.attribute(package.path.raw))\" obsolete=\"false\">"
    out += "<type-details xmlns:xsi=\"\(Self.schemaInstanceNamespace)\""
    out += " xsi:type=\"ns3:\(Self.attribute(source.typeName))\""
    out += typeDetails.isEmpty ? "/>" : ">\(typeDetails)</type-details>"
    out += Self.node(source.revision)
    out += "<display-name>\(Self.text(package.displayName))</display-name>"
    out += "<uses-license ref=\"\(Self.attribute(license.id))\"/>"
    out += source.dependencies.map(Self.node) ?? ""
    out += "</localPackage></ns2:repository>"
    return Data(out.utf8)
  }

  /// `.element` 는 요소로, `.text` 는 공백만이면 버리고 아니면 이스케이프한 그대로.
  private static func node(_ node: AndroidXMLNode) -> String {
    switch node {
    case let .text(value):
      return value.unicodeScalars.allSatisfy { " \t\n\r".unicodeScalars.contains($0) } ? "" : Self.text(value)
    case let .element(name, attributes, children):
      let attrs = attributes.keys.sorted().map { " \($0)=\"\(Self.attribute(attributes[$0] ?? ""))\"" }.joined()
      let inner = Self.children(children)
      return inner.isEmpty ? "<\(name)\(attrs)/>" : "<\(name)\(attrs)>\(inner)</\(name)>"
    }
  }

  private static func children(_ nodes: [AndroidXMLNode]) -> String {
    nodes.map(self.node).joined()
  }

  /// 글자 마디: `&`·`<`·`>`·`\r` (그 밖 그대로). `\r\n` 이 한 글자로 묶이지 않게 유니코드 스칼라로 본다.
  static func text(_ value: String) -> String {
    self.escape(value) { scalar in
      switch scalar {
      case "&": "&amp;"
      case "<": "&lt;"
      case ">": "&gt;"
      case "\r": "&#13;"
      default: nil
      }
    }
  }

  /// 속성 값 (큰따옴표): `&`·`<`·`"`·`\t`·`\n`·`\r`.
  static func attribute(_ value: String) -> String {
    self.escape(value) { scalar in
      switch scalar {
      case "&": "&amp;"
      case "<": "&lt;"
      case "\"": "&quot;"
      case "\t": "&#9;"
      case "\n": "&#10;"
      case "\r": "&#13;"
      default: nil
      }
    }
  }

  private static func escape(_ value: String, _ replacement: (Unicode.Scalar) -> String?) -> String {
    var out = String.UnicodeScalarView()
    for scalar in value.unicodeScalars {
      if let replaced = replacement(scalar) {
        out.append(contentsOf: replaced.unicodeScalars)
      } else {
        out.append(scalar)
      }
    }
    return String(out)
  }
}
