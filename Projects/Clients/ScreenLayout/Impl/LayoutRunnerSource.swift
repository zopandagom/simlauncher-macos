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
    /// (앱 전환 직후 약 1~2.5초 동안 이전 앱과 새 앱이 함께 runningForeground 다). 그 사이 앞 앱이 여럿이어도
    /// 윈도우형 앱·스테이지 매니저에서 창이 겹친 상태(`frontWindowApp`)면 기다리지 않고 맨 앞 창의 앱만 읽는다.
    /// 앞 앱이 모두 화면에 카드로만 있으면(`AppCards.cardOnly`, 앱 전환기) 없는 것으로 본다. 앞 앱이 없으면 SpringBoard 를 읽는다.
    func snapshotForeground(candidates: [String], settle: Double) -> [String: Any] {
      let apps = candidates.filter { $0 != Self.springBoard }
      let deadline = Date().addingTimeInterval(settle)
      var foreground: [String] = []
      // 맨 앞 창을 고른 카드를 그대로 판정·좌표에 쓴다 (다시 읽으면 그 사이 창이 바뀌거나 읽기가 실패할 수 있다).
      var chosen: AppCards?
      while true {
        foreground = apps.filter { XCUIApplication(bundleIdentifier: $0).state == .runningForeground }
        if foreground.count <= 1 || Date() >= deadline {
          break
        }
        let cards = appCards()
        if let front = frontWindowApp(of: foreground, cards: cards) {
          foreground = [front]
          chosen = cards
          break
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
      }
      let cards = chosen ?? (foreground.isEmpty ? AppCards() : appCards())
      if !foreground.isEmpty, cards.cardOnly.isSuperset(of: foreground) {
        foreground = []
      }
      if foreground.isEmpty {
        return snapshot(of: [Self.springBoard], system: true)
      }
      return snapshot(of: foreground.sorted(), system: false, cards: cards)
    }

    /// SpringBoard 의 앱 카드(식별자 `card:<번들 ID>:…`). 앱이 실제로 보이면 카드 아래에 앱 장면이 붙고(`live`),
    /// 앱 전환기의 카드는 자식 없는 잎(`leaf`)이다. SpringBoard 를 읽지 못하면 모두 비어 있다.
    struct AppCards {
      var leaf: Set<String> = []
      var live: Set<String> = []
      /// 번들 ID 별 카드 frame (SpringBoard 좌표: 돌린 iPad 에서는 기기의 세로 좌표).
      var frames: [String: [CGRect]] = [:]
      /// SpringBoard 좌표 → 화면 좌표.
      var toScreen: (CGRect) -> CGRect = { $0 }

      /// 카드가 모두 잎인 앱. 앱 전환기에서도 마지막 앱은 runningForeground 로 남는다 (실측 iOS 27.0 iPad·iPhone,
      /// 전체 화면·윈도우형 앱, 세로·가로, iOS 27.1 iPhone Duo 바깥 화면). 앱을 띄운 직후(홈 아이콘 탭·simctl launch·
      /// 앱에서 앱으로)에도 앞 앱이 된 첫 판정부터 카드에 앱 장면이 붙어 있었다 (iPhone 17, 23번). 윈도우형 앱에서는 다른 창 뒤의
      /// 창 카드도 (일부만 가려져 보여도) 잎이라, 앞 앱이 모두 잎일 때만 쓴다 (맨 앞 창이 있으면 읽는다. 겹친 창은
      /// `frontWindowApp` 이 맨 앞 창의 앱만 고른다). 카드가 없는 앱(Spotlight)은 넣지 않는다 (앞 앱을 그대로 읽는다).
      var cardOnly: Set<String> {
        self.leaf.subtracting(self.live)
      }
    }

    /// 앞 앱 가운데 카드에 앱 장면이 붙은(`live`) 앱이 하나뿐이고 나머지 앞 앱은 모두 카드가 잎뿐이면 그 앱 (아니면 nil).
    /// 윈도우형 앱·스테이지 매니저에서 창이 겹치면 겹친 창의 앱이 모두 runningForeground 로 계속 남고, 앱 장면은 맨 앞 창의
    /// 카드에만 붙는다 (일부만 가려져 보이는 뒤 창도 잎. 실측 iOS 27.0 iPad Pro 11, 세로·가로). 전체 화면 앱을 바꾸는 중에는
    /// 이전 앱의 카드가 잎으로 남지 않고 사라지고 두 카드에 모두 장면이 붙는 때도 있어(실측 6번) 여기에 들지 않는다 (지금처럼 기다린다).
    /// 카드가 없는 앱(Spotlight)이 섞이거나 SpringBoard 를 읽지 못해도 nil 이다.
    func frontWindowApp(of foreground: [String], cards: AppCards) -> String? {
      let front = foreground.filter { cards.live.contains($0) }
      guard front.count == 1 else { return nil }
      let others = foreground.filter { $0 != front[0] }
      guard others.allSatisfy({ cards.cardOnly.contains($0) }) else { return nil }
      return front[0]
    }

    /// SpringBoard 를 읽어 앱 카드를 모은다. 카드 아래는 내려가지 않고, 그 밖의 상태 막대로 화면 방향(`screenTransform`)을 정한다.
    func appCards() -> AppCards {
      guard let root = try? XCUIApplication(bundleIdentifier: Self.springBoard).snapshot() else { return AppCards() }
      var cards = AppCards()
      var statusBars: [CGRect] = []
      var stack: [XCUIElementSnapshot] = [root]
      while let element = stack.popLast() {
        let parts = element.identifier.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count >= 2, parts[0] == "card" {
          let id = String(parts[1])
          if element.children.isEmpty {
            cards.leaf.insert(id)
          } else {
            cards.live.insert(id)
          }
          cards.frames[id, default: []].append(element.frame)
          continue
        }
        if element.elementType == .statusBar {
          statusBars.append(element.frame)
        }
        stack.append(contentsOf: element.children.reversed())
      }
      cards.toScreen = Self.screenTransform(statusBars: statusBars, root: root.frame)
      return cards
    }

    /// SpringBoard 좌표 → 화면 좌표. 돌린 iPad 의 SpringBoard 는 루트 밖 노드를 기기의 세로 좌표로 보고하므로, 전위 순서로 처음 나오는
    /// 띠 모양 상태 막대(짧은 변이 세로 폭의 ¼ 미만, 긴 변이 세로 크기의 한 변과 같고(0.5 안) 그 변에 붙음)가 붙은 쪽으로 방향을 정한다
    /// (호스트 `IOSLayoutConversion.rotation(of:root:)` 와 같은 규칙). 없으면 그대로 둔다.
    static func screenTransform(statusBars: [CGRect], root: CGRect) -> (CGRect) -> CGRect {
      let width = min(root.width, root.height)
      let height = max(root.width, root.height)
      let near = { (value: CGFloat, target: CGFloat) in abs(value - target) <= 0.5 }
      for bar in statusBars {
        if near(bar.width, width), bar.height < width / 4 {
          if near(bar.minY, 0) {
            return { $0 }
          }
          if near(bar.maxY, height) {
            return { CGRect(x: width - $0.maxX, y: height - $0.maxY, width: $0.width, height: $0.height) }
          }
        } else if near(bar.height, height), bar.width < width / 4 {
          if near(bar.minX, 0) {
            return { CGRect(x: height - $0.maxY, y: $0.minX, width: $0.height, height: $0.width) }
          }
          if near(bar.maxX, width) {
            return { CGRect(x: $0.minY, y: width - $0.maxX, width: $0.height, height: $0.width) }
          }
        }
      }
      return { $0 }
    }

    /// 앞 앱이 여럿이면 차례로 읽고, 읽지 못한 앱이 이제 앞에 없으면 빼고 계속한다 (전환이 settle 보다 길었던 경우).
    /// 모두 빠지면 notForeground. 앱(시스템 화면이 아님)은 `windowOffset` 만큼 옮겨 화면 좌표로 쓴다.
    func snapshot(of bundleIDs: [String], system: Bool, cards: AppCards = AppCards()) -> [String: Any] {
      var nodes: [[String: Any]] = []
      var read: [String] = []
      for id in bundleIDs {
        let app = XCUIApplication(bundleIdentifier: id)
        do {
          let root = try app.snapshot()
          let offset = system ? CGVector.zero : windowOffset(of: id, root: root, cards: cards)
          self.walk(root, depth: 0, offset: offset, into: &nodes)
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

    /// 앱 스냅샷 좌표 → 화면 좌표로 옮길 양. 윈도우형 앱·스테이지 매니저의 앱 스냅샷은 창 안 좌표(창 왼쪽 위가 0,0)로 오고,
    /// 그 앱의 SpringBoard 카드 frame 이 창 위치다 (실측 iOS 27.0 iPad Pro 11: 세로 230,305, 가로는 기기 세로 좌표로 와
    /// 화면 418,135. 전체 화면 앱은 카드가 화면 전체라 옮기지 않는다). 카드가 하나가 아니거나, 화면 좌표로 돌린 카드 크기가
    /// 스냅샷의 첫 창과 0.5pt 넘게 다르면 옮기지 않는다 (뒤 창의 잎 카드는 조금 작게 온 적이 있다).
    /// 창 질의 `windows.firstMatch` 의 frame 도 화면 좌표지만 쓰지 않는다: 없는 요소의 frame 은 테스트를 실패시켜 러너가 끝나고,
    /// 창 요소의 스냅샷 frame 은 창 안 좌표(0,0)다.
    func windowOffset(of id: String, root: XCUIElementSnapshot, cards: AppCards) -> CGVector {
      guard let local = root.children.first(where: { $0.elementType == .window })?.frame,
            let frames = cards.frames[id], frames.count == 1
      else { return .zero }
      let screen = cards.toScreen(frames[0])
      guard abs(local.width - screen.width) <= 0.5, abs(local.height - screen.height) <= 0.5 else { return .zero }
      return CGVector(dx: screen.minX - local.minX, dy: screen.minY - local.minY)
    }

    /// 전위 순서로 평평하게 쓴다 (d = 깊이, t = elementType 원시 값, 좌표는 pt, `offset` 만큼 옮긴다).
    func walk(_ element: XCUIElementSnapshot, depth: Int, offset: CGVector, into nodes: inout [[String: Any]]) {
      guard nodes.count <= Self.maxNodes else { return }
      let frame = element.frame
      var node: [String: Any] = [
        "d": depth,
        "t": Int(element.elementType.rawValue),
        "x": Double(frame.origin.x + offset.dx),
        "y": Double(frame.origin.y + offset.dy),
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
        walk(child, depth: depth + 1, offset: offset, into: &nodes)
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
