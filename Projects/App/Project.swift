import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.app(
  infoPlist: [
    "CFBundleDisplayName": "SimLauncher",
  ],
  dependencies: [
    .feature(.launcher),
    .client(impl: .simulator),
    .shared(.core),
  ]
)
