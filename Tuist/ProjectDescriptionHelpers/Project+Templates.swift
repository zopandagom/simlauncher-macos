import ProjectDescription

public enum Env {
  public static let appName = "SimLauncher"
  public static let bundleIdPrefix = "com.zopandagom.simlauncher"
  public static let destinations: Destinations = [.mac]
  public static let deploymentTargets: DeploymentTargets = .macOS("26.0")
  /// 앱 타깃(App·Example) Info.plist 에 공통으로 넣는 값.
  static let appInfoPlist: [String: Plist.Value] = [:]
  /// Apple Developer Program 팀 ID(공개 값). 배포는 `make release` 가 Xcode 자동 서명(클라우드 관리 Developer ID 인증서)으로 내보낸다.
  /// 개발 실행은 `CODE_SIGN_IDENTITY = "-"`(Tuist 기본)라 ad-hoc 으로 돌고, `make build`·`make test`·CI 는 서명하지 않는다.
  static let developmentTeam = "XHV4ZL5K8T"
  /// 배포 버전. `make release` 가 dmg 이름(`SimLauncher-<버전>.dmg`)에 쓴다. 올릴 때 여기만 고친다 (docs/RELEASING.md).
  static let marketingVersion = "1.0.0"
  /// 빌드 번호. 같은 버전을 다시 배포하면 올린다.
  static let buildNumber = "1"
  /// 앱 타깃(`SimLauncher`)에만 주는 설정. Example 앱·모듈·테스트에는 주지 않는다.
  static let appTargetSettings: SettingsDictionary = [
    // 공증 필수. entitlement 없이 simctl·xcodebuild·URLSession 등이 돈다 (실측, docs/RELEASING.md)
    "ENABLE_HARDENED_RUNTIME": "YES",
    "MARKETING_VERSION": .string(Self.marketingVersion),
    "CURRENT_PROJECT_VERSION": .string(Self.buildNumber),
  ]
  /// 앱 타깃 Info.plist 에만 넣는 값. Tuist 기본 Info.plist 의 고정 버전(1.0·1)과 빈 저작권 문구를 바꾼다.
  static let appVersionInfoPlist: [String: Plist.Value] = [
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "NSHumanReadableCopyright": "Copyright © 2026 Joongwon Kim. MIT License.",
  ]
  /// 화면 문자열은 한국어 먼저. 모든 프로젝트가 같은 개발 언어를 써야 String Catalog 의 원문 언어가 맞는다.
  static let projectOptions: Project.Options = .options(defaultKnownRegions: ["ko", "en"], developmentRegion: "ko")

  static let baseSettings: SettingsDictionary = [
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "CODE_SIGN_STYLE": "Automatic",
    "DEVELOPMENT_TEAM": .string(Self.developmentTeam),
    // Xcode 에서 빌드할 때 코드의 문자열이 String Catalog(`Localizable.xcstrings`)에 추가된다.
    // `xcodebuild`(make·CI)는 카탈로그를 고치지 않으므로 CLI 로만 작업하면 항목을 직접 넣는다.
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
  ]

  static func bundleId(_ name: String) -> String {
    "\(self.bundleIdPrefix).\(name.lowercased())"
  }
}

public extension Project {
  /// 앱 조립 지점. Feature 와 Client Impl 을 모두 알고 있는 유일한 모듈.
  static func app(infoPlist: [String: Plist.Value], dependencies: [TargetDependency]) -> Project {
    Project(
      name: "App",
      options: Env.projectOptions,
      settings: .settings(base: Env.baseSettings),
      targets: [
        .target(
          name: Env.appName,
          destinations: Env.destinations,
          product: .app,
          bundleId: Env.bundleIdPrefix,
          deploymentTargets: Env.deploymentTargets,
          infoPlist: .extendingDefault(
            with: Env.appInfoPlist.merging(Env.appVersionInfoPlist) { $1 }.merging(infoPlist) { $1 }
          ),
          buildableFolders: ["Sources", "Resources"],
          dependencies: dependencies,
          settings: .settings(base: Env.appTargetSettings)
        ),
      ]
    )
  }

  /// Client 모듈: Interface(프로토콜·값 타입) / Impl(Apple 프레임워크 구현 또는 다른 Client 조합) / Testing(Fake) / Tests.
  /// - Parameters:
  ///   - clients: Impl 이 조합하는 다른 Client. Impl 에는 Interface 가, Tests 에는 Interface 와 Fake 가 든 Testing 이 연결된다.
  ///   - shared: Client 가 사용하는 Shared 모듈. 네 타깃 모두에 연결된다.
  static func client(
    _ client: Client,
    clients: [Client] = [],
    shared: [Shared] = [],
    interfaceDependencies: [TargetDependency] = [],
    implDependencies: [TargetDependency] = []
  ) -> Project {
    let shared = shared.map { TargetDependency.shared($0) }
    let otherInterfaces = clients.map { TargetDependency.client(interface: $0) }
    let otherTestings = clients.map { TargetDependency.client(testing: $0) }
    return Project(
      name: client.rawValue,
      options: Env.projectOptions,
      settings: .settings(base: Env.baseSettings),
      targets: [
        .module(name: client.interface, sources: "Interface", dependencies: shared + interfaceDependencies),
        .module(
          name: client.impl,
          sources: "Impl",
          dependencies: [.target(name: client.interface)] + shared + otherInterfaces + implDependencies
        ),
        .module(
          name: client.testing,
          sources: "Testing",
          dependencies: [.target(name: client.interface)] + shared
        ),
        .tests(
          name: client.tests,
          dependencies: [.target(name: client.impl), .target(name: client.testing)] + shared + otherInterfaces
            + otherTestings
        ),
      ]
    )
  }

  /// Feature 모듈: Feature(Model + View) / Tests / Example(Fake 로 단독 실행되는 데모 앱).
  /// - Parameters:
  ///   - clients: Feature 가 사용하는 Client. Feature 에는 Interface 가, Tests·Example 에는 Testing 이 연결된다.
  ///   - shared: Feature 가 사용하는 Shared 모듈. Feature·Tests·Example 모두에 연결된다.
  static func feature(
    _ feature: Feature,
    clients: [Client] = [],
    shared: [Shared] = []
  ) -> Project {
    let testing = clients.map { TargetDependency.client(testing: $0) }
    let shared = shared.map { TargetDependency.shared($0) }
    return Project(
      name: feature.name,
      options: Env.projectOptions,
      settings: .settings(base: Env.baseSettings),
      targets: [
        .module(
          name: feature.name,
          sources: "Sources",
          dependencies: clients.map { .client(interface: $0) } + shared
        ),
        .tests(name: feature.tests, dependencies: [.target(name: feature.name)] + testing + shared),
        .target(
          name: feature.example,
          destinations: Env.destinations,
          product: .app,
          bundleId: Env.bundleId(feature.example),
          deploymentTargets: Env.deploymentTargets,
          infoPlist: .extendingDefault(with: Env.appInfoPlist),
          buildableFolders: ["Example"],
          dependencies: [.target(name: feature.name)] + testing + shared
        ),
      ]
    )
  }

  /// Shared 모듈: 모듈 / Tests. 다른 모듈에 의존하지 않는다.
  static func shared(_ shared: Shared) -> Project {
    Project(
      name: shared.name,
      options: Env.projectOptions,
      settings: .settings(base: Env.baseSettings),
      targets: [
        .module(name: shared.name, sources: "Sources", dependencies: []),
        .tests(name: shared.tests, dependencies: [.target(name: shared.name)]),
      ]
    )
  }
}

extension Target {
  static func module(name: String, sources: String, dependencies: [TargetDependency]) -> Target {
    .target(
      name: name,
      destinations: Env.destinations,
      product: .staticFramework,
      bundleId: Env.bundleId(name),
      deploymentTargets: Env.deploymentTargets,
      buildableFolders: [.folder(.relativeToManifest(sources))],
      dependencies: dependencies
    )
  }

  static func tests(name: String, dependencies: [TargetDependency]) -> Target {
    .target(
      name: name,
      destinations: Env.destinations,
      product: .unitTests,
      bundleId: Env.bundleId(name),
      deploymentTargets: Env.deploymentTargets,
      buildableFolders: ["Tests"],
      dependencies: dependencies
    )
  }
}
