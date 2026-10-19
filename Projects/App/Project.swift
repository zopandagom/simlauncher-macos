import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.app(
  infoPlist: [
    "CFBundleDisplayName": "SimLauncher",
  ],
  dependencies: [
    .feature(.launcher),
    .client(impl: .command),
    .client(impl: .simulator),
    .client(impl: .appBundle),
    .shared(.core),
  ]
)
