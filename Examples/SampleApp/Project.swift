import ProjectDescription

// SimLauncher 카탈로그 예시 워크플로가 빌드하는 최소 iOS 앱. 메인 워크스페이스(Projects/**)에 들지 않는다.
let project = Project(
  name: "SampleApp",
  options: .options(defaultKnownRegions: ["ko", "en"], developmentRegion: "ko"),
  settings: .settings(base: [
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "MARKETING_VERSION": "1.0.0",
    "CURRENT_PROJECT_VERSION": "1",
  ]),
  targets: [
    .target(
      name: "SampleApp",
      destinations: [.iPhone, .iPad],
      product: .app,
      bundleId: "com.zopandagom.simlauncher.sampleapp",
      deploymentTargets: .iOS("17.0"),
      infoPlist: .extendingDefault(with: [
        "UILaunchScreen": [:],
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
      ]),
      buildableFolders: ["Sources"]
    ),
  ]
)
