import Core
import Foundation
import Testing
@testable import ScreenLayoutImpl

/// 동봉 러너 소스 검사. `make build` 는 러너 Swift 를 컴파일하지 않으므로 형식·이름·호스트와의 규약을 여기서 본다
/// (실제 빌드는 `make layout-runner-check`).
struct LayoutRunnerSourceTests {
  @Test("파일 세 개를 프로젝트·스킴·Swift 경로로 낸다")
  func paths() {
    #expect(LayoutRunnerSource.files.map(\.path) == [
      "LayoutRunner.xcodeproj/project.pbxproj",
      "LayoutRunner.xcodeproj/xcshareddata/xcschemes/LayoutRunner.xcscheme",
      "Sources/LayoutRunnerTests.swift",
    ])
    #expect(LayoutRunnerSource.files.allSatisfy { !$0.contents.isEmpty })
  }

  @Test("pbxproj 는 plist 로 읽히고 제품 이름·번들 ID·최소 iOS·UI 테스트 타깃이 Core 의 러너 정체와 같다")
  func project() throws {
    let data = Data(LayoutRunnerSource.project.utf8)
    let plist = try #require(
      try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    )
    let objects = try #require(plist["objects"] as? [String: [String: Any]])
    let settings = objects.values.compactMap { $0["buildSettings"] as? [String: Any] }
    #expect(settings.contains { $0["PRODUCT_NAME"] as? String == IOSLayoutRunner.productName })
    #expect(settings.contains { $0["PRODUCT_BUNDLE_IDENTIFIER"] as? String == IOSLayoutRunner.testBundleID })
    #expect(settings.contains { $0["ALWAYS_SEARCH_USER_PATHS"] as? String == "NO" })
    let deploymentTargets = settings.compactMap { $0["IPHONEOS_DEPLOYMENT_TARGET"] as? String }
    #expect(deploymentTargets.compactMap(OSVersion.init) == [IOSLayoutRunner.minimumOSVersion])
    let targets = objects.values.filter { $0["isa"] as? String == "PBXNativeTarget" }
    #expect(targets.count == 1)
    #expect(targets.first?["productType"] as? String == "com.apple.product-type.bundle.ui-testing")
    #expect(targets.first?["name"] as? String == LayoutRunnerSource.scheme)
  }

  @Test("스킴 XML 의 BuildableName 이 <제품 이름>.xctest 다")
  func scheme() {
    let collector = BuildableNameCollector()
    let parser = XMLParser(data: Data(LayoutRunnerSource.schemeXML.utf8))
    parser.delegate = collector
    #expect(parser.parse())
    #expect(!collector.names.isEmpty)
    #expect(collector.names.allSatisfy { $0 == "\(IOSLayoutRunner.productName).xctest" })
  }

  @Test("러너 Swift 원문에 환경 이름·RunLoop 대기·프로토콜 번호가 있다")
  func runnerTokens() {
    let tests = LayoutRunnerSource.tests
    for token in [
      "\"SIMLAUNCHER_LAYOUT_DIR\"", "\"SIMLAUNCHER_LAYOUT_SESSION\"", "\"SIMLAUNCHER_LAYOUT_IDLE\"",
      "RunLoop.current.run(until:", "static let protocolVersion = \(LayoutRunnerProtocol.version)",
      "import XCTest",
    ] {
      #expect(tests.contains(token), "\(token)")
    }
  }

  @Test("러너는 앞 앱이 모두 SpringBoard 카드로만 있으면(앱 전환기) SpringBoard 를 읽는다")
  func allCardOnlyReadsSpringBoard() throws {
    let tests = LayoutRunnerSource.tests
    for token in [
      "func appCards() -> AppCards", "XCUIApplication(bundleIdentifier: Self.springBoard).snapshot()",
      "parts[0] == \"card\"", "element.children.isEmpty", "self.leaf.subtracting(self.live)",
    ] {
      #expect(tests.contains(token), "\(token)")
    }
    // 판정은 settle 대기 뒤, SpringBoard 로 넘어가는 판정 앞에 있다.
    let filter = try #require(tests
      .range(of: "if !foreground.isEmpty, cards.cardOnly.isSuperset(of: foreground) {\n      foreground = []"))
    let settle = try #require(tests.range(of: "if foreground.count <= 1 || Date() >= deadline"))
    let fallback = try #require(tests
      .range(of: "if foreground.isEmpty {\n      return snapshot(of: [Self.springBoard]"))
    #expect(settle.upperBound < filter.lowerBound)
    #expect(filter.upperBound < fallback.lowerBound)
  }

  @Test("러너는 겹친 창의 앞 앱 중 맨 앞 창(카드에 장면이 붙은 앱 하나, 나머지는 잎)이 있으면 기다리지 않고 그 앱만 읽는다")
  func frontWindowReadsOnlyFrontApp() throws {
    let tests = LayoutRunnerSource.tests
    for token in [
      "func frontWindowApp(of foreground: [String], cards: AppCards) -> String?",
      "guard front.count == 1 else { return nil }", "others.allSatisfy({ cards.cardOnly.contains($0) })",
    ] {
      #expect(tests.contains(token), "\(token)")
    }
    // 판정은 settle 대기 루프 안, 앞 앱이 하나 이하인지·기한인지 본 뒤 0.2초 대기 앞에 있다.
    let settle = try #require(tests.range(of: "if foreground.count <= 1 || Date() >= deadline"))
    let front = try #require(tests.range(
      of: "if let front = frontWindowApp(of: foreground, cards: cards) {\n"
        + "        foreground = [front]\n        chosen = cards\n        break"
    ))
    // 고른 카드를 루프 뒤 판정·좌표에 그대로 쓴다 (다시 읽지 않는다).
    #expect(tests.contains("let cards = chosen ?? (foreground.isEmpty ? AppCards() : appCards())"))
    let wait = try #require(tests.range(of: "RunLoop.current.run(until: Date().addingTimeInterval(0.2))"))
    #expect(settle.upperBound < front.lowerBound)
    #expect(front.upperBound < wait.lowerBound)
  }

  @Test("러너는 앱 노드를 화면 좌표로 돌린 카드 위치만큼 옮기고, 시스템 화면·카드 크기가 다른 앱은 옮기지 않는다")
  func appNodesMoveByCardOrigin() {
    let tests = LayoutRunnerSource.tests
    for token in [
      "return snapshot(of: foreground.sorted(), system: false, cards: cards)",
      "let offset = system ? CGVector.zero : windowOffset(of: id, root: root, cards: cards)",
      "let frames = cards.frames[id], frames.count == 1",
      "guard abs(local.width - screen.width) <= 0.5, abs(local.height - screen.height) <= 0.5 else { return .zero }",
      "cards.toScreen = Self.screenTransform(statusBars: statusBars, root: root.frame)",
      "\"x\": Double(frame.origin.x + offset.dx)", "\"y\": Double(frame.origin.y + offset.dy)",
      "walk(child, depth: depth + 1, offset: offset, into: &nodes)",
    ] {
      #expect(tests.contains(token), "\(token)")
    }
    // 방향 판정과 변환식은 호스트 `IOSLayoutConversion.rotation(of:root:)`·`ScreenRotation.apply` 와 같다.
    for token in [
      "if near(bar.width, width), bar.height < width / 4 {", "if near(bar.minY, 0) {", "if near(bar.maxY, height) {",
      "return { CGRect(x: width - $0.maxX, y: height - $0.maxY, width: $0.width, height: $0.height) }",
      "} else if near(bar.height, height), bar.width < width / 4 {", "if near(bar.minX, 0) {",
      "return { CGRect(x: height - $0.maxY, y: $0.minX, width: $0.height, height: $0.width) }",
      "if near(bar.maxX, width) {",
      "return { CGRect(x: $0.minY, y: width - $0.maxX, width: $0.height, height: $0.width) }",
    ] {
      #expect(tests.contains(token), "\(token)")
    }
    // 없는 요소의 frame 은 테스트를 실패시켜 러너가 끝나므로 창 질의 frame 을 쓰지 않는다.
    #expect(!tests.contains(".firstMatch.frame"))
  }

  @Test("호스트가 쓰는 파일·환경·키·명령·실패 값이 모두 러너 원문에 따옴표 문자열로 있다")
  func contract() {
    let tests = LayoutRunnerSource.tests
    for name in LayoutRunnerProtocol.runnerContract {
      #expect(tests.contains("\"\(name)\""), "\(name)")
    }
    for field in LayoutRunnerProtocol.runnerRequestFields {
      #expect(tests.contains("let \(field):"), "\(field)")
    }
  }

  @Test("digest 는 같은 입력에 같고 한 글자 바뀌면 다르다")
  func digest() {
    let files = LayoutRunnerSource.files
    var changed = files
    changed[2].contents += " "
    #expect(LayoutRunnerSource.digest(of: files) == LayoutRunnerSource.digest)
    #expect(LayoutRunnerSource.digest.count == 64)
    #expect(LayoutRunnerSource.digest(of: changed) != LayoutRunnerSource.digest)
  }

  @Test("폴더에 쓰면 경로마다 내용 + 줄바꿈 하나")
  func write() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "LayoutRunnerSource-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }

    try LayoutRunnerSource.write(to: folder)

    for file in LayoutRunnerSource.files {
      let written = try String(contentsOf: folder.appending(path: file.path), encoding: .utf8)
      #expect(written == file.contents + "\n")
    }
  }
}

private final class BuildableNameCollector: NSObject, XMLParserDelegate {
  var names: [String] = []

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    if elementName == "BuildableReference", let name = attributeDict["BuildableName"] {
      self.names.append(name)
    }
  }
}

/// `make layout-runner-check` 가 부르는 내보내기: 환경 `SIMLAUNCHER_EXPORT_LAYOUT_RUNNER`(xcodebuild 에 `TEST_RUNNER_` 접두로 넘긴 값)가
/// 있을 때만 그 폴더에 러너 소스를 쓴다. 그 뒤 Makefile 이 실제로 빌드한다.
struct LayoutRunnerSourceExportTests {
  static let exportPath = ProcessInfo.processInfo.environment["SIMLAUNCHER_EXPORT_LAYOUT_RUNNER"]

  @Test("러너 소스를 환경이 가리키는 폴더로 내보낸다", .enabled(if: Self.exportPath?.isEmpty == false))
  func export() throws {
    let path = try #require(Self.exportPath)
    let folder = URL(filePath: path, directoryHint: .isDirectory)
    try? FileManager.default.removeItem(at: folder)

    try LayoutRunnerSource.write(to: folder)

    #expect(FileManager.default.fileExists(atPath: folder.appending(path: LayoutRunnerSource.projectPath).path))
  }
}
