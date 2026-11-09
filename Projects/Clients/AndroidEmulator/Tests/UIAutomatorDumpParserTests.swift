import AndroidEmulatorInterface
import Core
import Foundation
import Testing
@testable import AndroidEmulatorImpl

struct UIAutomatorDumpParserTests {
  static func dump(_ body: String) -> Data {
    Data("<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation=\"0\">\(body)</hierarchy>".utf8)
  }

  static func node(
    _ bounds: String,
    class type: String = "android.view.View",
    package: String = "com.example.app",
    text: String = "",
    id: String = "",
    desc: String = "",
    children: String = ""
  ) -> String {
    """
    <node index="0" text="\(text)" resource-id="\(id)" class="\(type)" package="\(package)" content-desc="\(desc)" \
    checkable="false" clickable="false" enabled="true" bounds="\(bounds)" drawing-order="0" hint="">\(children)</node>
    """
  }

  @Test("노드를 전위 순서로 읽고 깊이·부모 번호를 매긴다")
  func preorder() throws {
    let xml = Self.dump(Self.node(
      "[0,0][1080,2400]",
      class: "android.widget.FrameLayout",
      children: Self.node("[0,0][1080,168]", children: Self.node("[85,105][148,168]"))
        + Self.node("[0,168][1080,2400]")
    ))

    let parsed = try UIAutomatorDumpParser.parse(xml)

    #expect(parsed.nodes.map(\.id) == [0, 1, 2, 3])
    #expect(parsed.nodes.map(\.depth) == [0, 1, 2, 1])
    #expect(parsed.nodes.map(\.parentID) == [nil, 0, 1, 0])
    #expect(parsed.nodes[0].type == "android.widget.FrameLayout")
    #expect(parsed.nodes[2].frame == LayoutRect(x: 85, y: 105, width: 63, height: 63))
  }

  @Test("속성: resource-id·text·content-desc, 빈 값은 nil")
  func attributes() throws {
    let xml = Self.dump(
      Self.node("[0,0][10,10]", text: "Wi-Fi", id: "android:id/title", desc: "Navigate up")
        + Self.node("[0,0][10,10]")
    )

    let parsed = try UIAutomatorDumpParser.parse(xml)

    #expect(parsed.nodes[0].identifier == "android:id/title")
    #expect(parsed.nodes[0].text == "Wi-Fi")
    #expect(parsed.nodes[0].label == "Navigate up")
    #expect(parsed.nodes[1].identifier == nil)
    #expect(parsed.nodes[1].text == nil)
    #expect(parsed.nodes[1].label == nil)
  }

  @Test("XML 이스케이프된 텍스트는 풀어서 담는다")
  func escapedText() throws {
    let parsed = try UIAutomatorDumpParser.parse(Self.dump(Self.node(
      "[0,0][10,10]",
      text: "A &amp; B &lt;C&gt; &quot;D&quot;"
    )))

    #expect(parsed.nodes[0].text == "A & B <C> \"D\"")
  }

  @Test("뒤집힌 bounds 는 음수 크기 그대로, 형식 오류·없는 bounds 는 크기 0 (노드는 남긴다)")
  func bounds() throws {
    let xml = Self.dump(
      Self.node("[0,294][2400,154]")
        + Self.node("[0,0][10]")
        + Self.node("[0,0][1234567890,10]")
        + Self.node("[ 0,0][10,10]")
        + "<node class=\"x\" />"
        + Self.node("[-10,-20][30,40]")
    )

    let parsed = try UIAutomatorDumpParser.parse(xml)

    #expect(parsed.nodes.count == 6)
    #expect(parsed.nodes[0].frame == LayoutRect(x: 0, y: 294, width: 2400, height: -140))
    let zero = LayoutRect(x: 0, y: 0, width: 0, height: 0)
    #expect(parsed.nodes[1].frame == zero)
    #expect(parsed.nodes[2].frame == zero)
    #expect(parsed.nodes[3].frame == zero)
    #expect(parsed.nodes[4].frame == zero)
    #expect(parsed.nodes[5].frame == LayoutRect(x: -10, y: -20, width: 40, height: 60))
  }

  @Test("9자리 bounds 끼리 빼도 넘치지 않는다")
  func boundsNoOverflow() throws {
    let parsed = try UIAutomatorDumpParser.parse(Self.dump(Self.node("[-999999999,-999999999][999999999,999999999]")))

    #expect(parsed.nodes[0].frame.width == 1_999_999_998)
  }

  @Test("노드 0개는 성공 (빈 목록, 앱 식별자 없음, 시스템 화면 아님)")
  func empty() throws {
    let parsed = try UIAutomatorDumpParser.parse(Self.dump(""))

    #expect(parsed.nodes.isEmpty)
    #expect(parsed.appIdentifier == nil)
    #expect(!parsed.isSystemScreen)
  }

  @Test("앱 식별자는 첫 노드의 package, 모든 노드가 systemui 면 시스템 화면")
  func systemScreen() throws {
    let app = try UIAutomatorDumpParser.parse(Self.dump(
      Self.node(
        "[0,0][10,10]",
        package: "com.android.settings",
        children: Self.node("[0,0][5,5]", package: "com.android.systemui")
      )
    ))
    #expect(app.appIdentifier == "com.android.settings")
    #expect(!app.isSystemScreen)

    let shade = try UIAutomatorDumpParser.parse(Self.dump(
      Self.node(
        "[0,0][10,10]",
        package: "com.android.systemui",
        children: Self.node("[0,0][5,5]", package: "com.android.systemui")
      )
    ))
    #expect(shade.appIdentifier == "com.android.systemui")
    #expect(shade.isSystemScreen)
  }

  @Test("루트가 hierarchy 가 아니거나 XML 이 깨지면 거절")
  func rejectsMalformed() {
    #expect(throws: AndroidEmulatorError.layoutUnreadable) {
      try UIAutomatorDumpParser.parse(Data("<root><node bounds=\"[0,0][1,1]\"/></root>".utf8))
    }
    #expect(throws: AndroidEmulatorError.layoutUnreadable) {
      try UIAutomatorDumpParser.parse(Data("<hierarchy><node bounds=\"[0,0][1,1]\">".utf8))
    }
    #expect(throws: AndroidEmulatorError.layoutUnreadable) {
      try UIAutomatorDumpParser.parse(Data())
    }
  }

  @Test("노드 수 상한을 넘으면 거절, 상한까지는 읽는다")
  func nodeLimit() throws {
    let leaf = "<node bounds=\"[0,0][1,1]\" class=\"v\" package=\"p\"/>"
    let atLimit = Self.dump(String(repeating: leaf, count: UIAutomatorDumpParser.maxNodes))
    #expect(try UIAutomatorDumpParser.parse(atLimit).nodes.count == UIAutomatorDumpParser.maxNodes)

    let over = Self.dump(String(repeating: leaf, count: UIAutomatorDumpParser.maxNodes + 1))
    #expect(throws: AndroidEmulatorError.layoutUnreadable) {
      try UIAutomatorDumpParser.parse(over)
    }
  }

  @Test("깊이 상한을 넘으면 거절")
  func depthLimit() {
    let depth = UIAutomatorDumpParser.maxDepth + 2
    let xml = Self.dump(
      String(repeating: "<node bounds=\"[0,0][1,1]\">", count: depth) + String(repeating: "</node>", count: depth)
    )

    #expect(throws: AndroidEmulatorError.layoutUnreadable) {
      try UIAutomatorDumpParser.parse(xml)
    }
  }

  @Test("입력 바이트 상한을 넘으면 해석하지 않고 거절")
  func byteLimit() {
    var xml = Self.dump(Self.node("[0,0][1,1]"))
    xml.append(Data(repeating: 0x20, count: UIAutomatorDumpParser.maxBytes))

    #expect(throws: AndroidEmulatorError.layoutUnreadable) {
      try UIAutomatorDumpParser.parse(xml)
    }
  }

  @Test("실측 표본 모양(꼬리 문구를 자른 덤프)도 읽는다")
  func realShape() throws {
    let output = try #require(String(
      bytes: Self.dump(Self.node("[0,0][1080,2400]", package: "com.android.settings")),
      encoding: .utf8
    ))
      + "UI hierchary dumped to: /dev/tty\n"
    let result = ADBLayoutCommandsTests.result(stdout: output)

    let parsed = try UIAutomatorDumpParser.parse(ADBLayoutCommands.classifyDump(result).get())

    #expect(parsed.nodes.count == 1)
    #expect(parsed.appIdentifier == "com.android.settings")
  }
}
