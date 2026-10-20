import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.app(
  infoPlist: [
    "CFBundleDisplayName": "SimLauncher",
  ],
  dependencies: [
    .feature(.launcher),
    .feature(.setup),
    .client(impl: .command),
    .client(impl: .devEnvironment),
    .client(impl: .simulator),
    .client(impl: .appBundle),
    .shared(.core),
  ]
)
