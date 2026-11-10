import CryptoKit
import Foundation

/// SimLauncher 가 사용자 Mac 에서 처음 쓸 때 빌드하는 iOS 레이아웃 러너(XCUITest) 소스. 앱 바이너리에 원시 문자열로 들어 있다
/// (리소스 번들이 아니다: Tuist 템플릿·gitignore·lint 설정을 바꾸지 않고, 번들 복사 실수로 빠지는 실패 경로가 없다).
/// `make build` 는 이 Swift 원문을 컴파일하지 않는다 → `make layout-runner-check`(내보내 실제 빌드)와 원문 검사 테스트로 막는다.
/// 바꿀 때는 `LayoutRunnerProtocol.runnerContract`(호스트와 맞춰야 하는 이름)와 `IOSLayoutRunner`(Core, 번들 ID)를 함께 본다.
enum LayoutRunnerSource {
  /// `xcodebuild -project` 에 넘기는 프로젝트 폴더 이름.
  static let projectFolder = "LayoutRunner.xcodeproj"
  /// `xcodebuild -scheme` 에 넘기는 스킴 이름.
  static let scheme = "LayoutRunner"
  static let projectPath = "LayoutRunner.xcodeproj/project.pbxproj"
  static let schemePath = "LayoutRunner.xcodeproj/xcshareddata/xcschemes/LayoutRunner.xcscheme"
  static let testsPath = "Sources/LayoutRunnerTests.swift"

  /// 쓸 파일 (소스 폴더 기준 상대 경로, 내용).
  static let files: [(path: String, contents: String)] = [
    (projectPath, project),
    (schemePath, schemeXML),
    (testsPath, tests),
  ]

  /// `files` 의 SHA-256 (소문자 16진수). 빌드 키에 들어가 소스가 바뀌면 다시 빌드한다.
  static let digest = Self.digest(of: files)

  /// 경로·내용을 차례로 NUL 로 나눠 이은 바이트의 SHA-256.
  static func digest(of files: [(path: String, contents: String)]) -> String {
    var hasher = SHA256()
    for file in files {
      hasher.update(data: Data(file.path.utf8))
      hasher.update(data: Data([0]))
      hasher.update(data: Data(file.contents.utf8))
      hasher.update(data: Data([0]))
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  /// `directory` 아래에 `files` 를 쓴다 (중간 폴더를 만들고, 각 파일 끝에 줄바꿈 하나).
  static func write(to directory: URL) throws {
    for file in self.files {
      let url = directory.appending(path: file.path, directoryHint: .notDirectory)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data((file.contents + "\n").utf8).write(to: url, options: .atomic)
    }
  }
}

// MARK: - LayoutRunner.xcodeproj/project.pbxproj

extension LayoutRunnerSource {
  /// 손으로 쓴 최소 pbxproj: UI 테스트 타깃 하나, 호스트 앱 없음, 서명 없음(`-`), Info.plist 생성.
  static let project = #"""
  // !$*UTF8*$!
  {
    archiveVersion = 1;
    classes = {};
    objectVersion = 56;
    objects = {
      A0000000000000000000001 = {isa = PBXBuildFile; fileRef = A0000000000000000000002; };
      A0000000000000000000002 = {
        isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LayoutRunnerTests.swift;
        sourceTree = "<group>";
      };
      A0000000000000000000003 = {
        isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0;
        path = SimLauncherLayout.xctest;
        sourceTree = BUILT_PRODUCTS_DIR;
      };
      A0000000000000000000010 = {
        isa = PBXGroup; children = (A0000000000000000000011, A0000000000000000000012); sourceTree = "<group>";
      };
      A0000000000000000000011 = {
        isa = PBXGroup; children = (A0000000000000000000002); path = Sources; sourceTree = "<group>";
      };
      A0000000000000000000012 = {
        isa = PBXGroup; children = (A0000000000000000000003); name = Products; sourceTree = "<group>";
      };
      A0000000000000000000020 = {
        isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (A0000000000000000000001);
        runOnlyForDeploymentPostprocessing = 0;
      };
      A0000000000000000000030 = {
        isa = PBXNativeTarget; buildConfigurationList = A0000000000000000000041;
        buildPhases = (A0000000000000000000020); buildRules = (); dependencies = ();
        name = LayoutRunner; productName = SimLauncherLayout; productReference = A0000000000000000000003;
        productType = "com.apple.product-type.bundle.ui-testing";
      };
      A0000000000000000000040 = {
        isa = XCConfigurationList; buildConfigurations = (A0000000000000000000050);
        defaultConfigurationName = Debug;
      };
      A0000000000000000000041 = {
        isa = XCConfigurationList; buildConfigurations = (A0000000000000000000051);
        defaultConfigurationName = Debug;
      };
      A0000000000000000000050 = {
        isa = XCBuildConfiguration;
        buildSettings = {
          SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0;
          CODE_SIGN_IDENTITY = "-"; CODE_SIGN_STYLE = Manual; COMPILER_INDEX_STORE_ENABLE = NO;
          ALWAYS_SEARCH_USER_PATHS = NO;
        };
        name = Debug;
      };
      A0000000000000000000051 = {
        isa = XCBuildConfiguration;
        buildSettings = {
          PRODUCT_NAME = SimLauncherLayout; PRODUCT_BUNDLE_IDENTIFIER = com.zopandagom.simlauncher.layoutrunner;
          GENERATE_INFOPLIST_FILE = YES; TARGETED_DEVICE_FAMILY = "1,2";
          SUPPORTED_PLATFORMS = "iphonesimulator iphoneos";
        };
        name = Debug;
      };
      A0000000000000000000060 = {
        isa = PBXProject; buildConfigurationList = A0000000000000000000040; compatibilityVersion = "Xcode 14.0";
        mainGroup = A0000000000000000000010; productRefGroup = A0000000000000000000012; projectDirPath = "";
        projectRoot = ""; targets = (A0000000000000000000030);
      };
    };
    rootObject = A0000000000000000000060;
  }
  """#
}

// MARK: - LayoutRunner.xcodeproj/xcshareddata/xcschemes/LayoutRunner.xcscheme

extension LayoutRunnerSource {
  /// 공유 스킴: 테스트 빌드만.
  static let schemeXML = #"""
  <?xml version="1.0" encoding="UTF-8"?>
  <Scheme LastUpgradeVersion = "1500" version = "1.7">
    <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
        <BuildActionEntry
          buildForTesting = "YES" buildForRunning = "NO" buildForProfiling = "NO" buildForArchiving = "NO"
          buildForAnalyzing = "NO">
          <BuildableReference
            BuildableIdentifier = "primary" BlueprintIdentifier = "A0000000000000000000030"
            BuildableName = "SimLauncherLayout.xctest" BlueprintName = "LayoutRunner"
            ReferencedContainer = "container:LayoutRunner.xcodeproj"/>
        </BuildActionEntry>
      </BuildActionEntries>
    </BuildAction>
    <TestAction
      buildConfiguration = "Debug" selectedDebuggerIdentifier = ""
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
        <TestableReference skipped = "NO">
          <BuildableReference
            BuildableIdentifier = "primary" BlueprintIdentifier = "A0000000000000000000030"
            BuildableName = "SimLauncherLayout.xctest" BlueprintName = "LayoutRunner"
            ReferencedContainer = "container:LayoutRunner.xcodeproj"/>
        </TestableReference>
      </Testables>
    </TestAction>
  </Scheme>
  """#
}

// MARK: - Sources/LayoutRunnerTests.swift

extension LayoutRunnerSource {
  /// 러너 본체. 요청·응답 파일 프로토콜은 `LayoutRunnerProtocol`.
  static let tests = #"""
  import UIKit
  import XCTest

  /// SimLauncher 레이아웃 러너 (프로토콜 1). SimLauncher 가 사용자 Mac 에서 빌드해 시뮬레이터에 띄운다.
  /// 테스트 메서드 하나가 요청 파일을 기다리며 상주하고, 요청마다 앞 앱(없으면 SpringBoard)의 접근성 스냅샷을
  /// JSON 으로 쓴다. 환경(xcodebuild 에 TEST_RUNNER_ 접두로 넘긴 값): SIMLAUNCHER_LAYOUT_DIR(요청·응답 폴더, 호스트 경로),
  /// SIMLAUNCHER_LAYOUT_SESSION(세션 토큰, ready.json 에 되돌려 쓴다),
  /// SIMLAUNCHER_LAYOUT_IDLE(요청 없이 기다릴 초, 기본 600).
  final class LayoutRunnerTests: XCTestCase {
    func testServe() {
      let env = ProcessInfo.processInfo.environment
      guard let path = env["SIMLAUNCHER_LAYOUT_DIR"], !path.isEmpty else { return }
      let server = LayoutServer(
        dir: URL(fileURLWithPath: path, isDirectory: true),
        session: env["SIMLAUNCHER_LAYOUT_SESSION"] ?? "",
        idle: TimeInterval(env["SIMLAUNCHER_LAYOUT_IDLE"] ?? "") ?? 600
      )
      server.serve()
    }
  }

  private struct LayoutRequest: Decodable {
    let id: String
    let command: String
    let bundleIDs: [String]?
    let settle: Double?
  }

  private final class LayoutServer {
    static let protocolVersion = 1
    static let springBoard = "com.apple.springboard"
    static let maxNodes = 20000
    static let maxText = 512

    let dir: URL
    let session: String
    let idle: TimeInterval

    init(dir: URL, session: String, idle: TimeInterval) {
      self.dir = dir
      self.session = session
      self.idle = idle
    }

    /// 요청을 기다린다. 대기는 RunLoop 로 한다 (Thread.sleep 이면 앱 상태 알림을 받지 못해 state 가 낡는다).
    func serve() {
      write("ready.json", [
        "protocol": Self.protocolVersion,
        "session": session,
        "pid": Int(ProcessInfo.processInfo.processIdentifier),
        "scale": Double(UIScreen.main.scale),
      ])
      let requestURL = dir.appendingPathComponent("request.json")
      var lastRequest = Date()
      while Date().timeIntervalSince(lastRequest) < idle {
        if let data = try? Data(contentsOf: requestURL) {
          try? FileManager.default.removeItem(at: requestURL)
          guard let request = try? JSONDecoder().decode(LayoutRequest.self, from: data) else {
            write("response.json", ["id": "", "error": "badRequest"])
            lastRequest = Date()
            continue
          }
          if request.command == "quit" {
            write("response.json", ["id": request.id, "ok": true])
            return
          }
          var body: [String: Any] = request.command == "snapshot"
            ? snapshotForeground(candidates: request.bundleIDs ?? [], settle: request.settle ?? 8)
            : ["error": "unknownCommand"]
          body["id"] = request.id
          write("response.json", body)
          lastRequest = Date()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
      }
    }

    /// 후보(SpringBoard 제외) 중 runningForeground 가 하나 이하가 될 때까지 0.2초 간격으로 settle 초까지 기다린다
    /// (앱 전환 직후 약 1~2.5초 동안 이전 앱과 새 앱이 함께 runningForeground 다). 없으면 SpringBoard 를 읽는다.
    func snapshotForeground(candidates: [String], settle: Double) -> [String: Any] {
      let apps = candidates.filter { $0 != Self.springBoard }
      let deadline = Date().addingTimeInterval(settle)
      var foreground: [String] = []
      while true {
        foreground = apps.filter { XCUIApplication(bundleIdentifier: $0).state == .runningForeground }
        if foreground.count <= 1 || Date() >= deadline {
          break
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
      }
      if foreground.isEmpty {
        return snapshot(of: [Self.springBoard], system: true)
      }
      return snapshot(of: foreground.sorted(), system: false)
    }

    /// 앞 앱이 여럿이면 차례로 읽고, 읽지 못한 앱이 이제 앞에 없으면 빼고 계속한다 (전환이 settle 보다 길었던 경우).
    /// 모두 빠지면 notForeground.
    func snapshot(of bundleIDs: [String], system: Bool) -> [String: Any] {
      var nodes: [[String: Any]] = []
      var read: [String] = []
      for id in bundleIDs {
        let app = XCUIApplication(bundleIdentifier: id)
        do {
          let root = try app.snapshot()
          self.walk(root, depth: 0, into: &nodes)
          read.append(id)
        } catch {
          if !system, app.state != .runningForeground { continue }
          return ["error": "snapshotFailed"]
        }
      }
      if read.isEmpty { return ["error": "notForeground"] }
      return [
        "apps": read,
        "system": system,
        "truncated": nodes.count > Self.maxNodes,
        "nodes": nodes,
      ]
    }

    /// 전위 순서로 평평하게 쓴다 (d = 깊이, t = elementType 원시 값, 좌표는 pt).
    func walk(_ element: XCUIElementSnapshot, depth: Int, into nodes: inout [[String: Any]]) {
      guard nodes.count <= Self.maxNodes else { return }
      let frame = element.frame
      var node: [String: Any] = [
        "d": depth,
        "t": Int(element.elementType.rawValue),
        "x": Double(frame.origin.x),
        "y": Double(frame.origin.y),
        "w": Double(frame.size.width),
        "h": Double(frame.size.height),
      ]
      if !element.identifier.isEmpty {
        node["i"] = String(element.identifier.prefix(Self.maxText))
      }
      if !element.label.isEmpty {
        node["l"] = String(element.label.prefix(Self.maxText))
      }
      if !element.title.isEmpty {
        node["ti"] = String(element.title.prefix(Self.maxText))
      }
      if let value = element.value {
        let text = String(describing: value)
        if !text.isEmpty {
          node["v"] = String(text.prefix(Self.maxText))
        }
      }
      nodes.append(node)
      for child in element.children {
        walk(child, depth: depth + 1, into: &nodes)
      }
    }

    /// 임시 파일에 쓴 뒤 rename(2) 로 바꿔 놓는다 (있는 파일도 원자적으로 바뀐다).
    func write(_ name: String, _ object: [String: Any]) {
      guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
      let tmp = dir.appendingPathComponent(name + ".tmp")
      let dst = dir.appendingPathComponent(name)
      guard (try? data.write(to: tmp)) != nil else { return }
      _ = rename(tmp.path, dst.path)
    }
  }
  """#
}
