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
      "func cardOnlyApps() -> Set<String>", "XCUIApplication(bundleIdentifier: Self.springBoard).snapshot()",
      "parts[0] == \"card\"", "element.children.isEmpty", "leaf.subtracting(live)",
    ] {
      #expect(tests.contains(token), "\(token)")
    }
    // 판정은 settle 대기 뒤, SpringBoard 로 넘어가는 판정 앞에 있다.
    let filter = try #require(tests
      .range(of: "if !foreground.isEmpty, cardOnlyApps().isSuperset(of: foreground) {\n      foreground = []"))
    let settle = try #require(tests.range(of: "if foreground.count <= 1 || Date() >= deadline"))
    let fallback = try #require(tests
      .range(of: "if foreground.isEmpty {\n      return snapshot(of: [Self.springBoard]"))
    #expect(settle.upperBound < filter.lowerBound)
    #expect(filter.upperBound < fallback.lowerBound)
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
