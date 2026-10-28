import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.app(
  infoPlist: [
    "CFBundleDisplayName": "SimLauncher",
  ],
  dependencies: [
    .feature(.launcher),
    .feature(.setup),
    .feature(.settings),
    .feature(.androidSetup),
    .client(impl: .command),
    .client(impl: .devEnvironment),
    .client(impl: .simulator),
    .client(impl: .appBundle),
    .client(impl: .download),
    .client(impl: .preferences),
    .client(impl: .workspace),
    .client(impl: .androidSDK),
    .shared(.core),
  ]
)
