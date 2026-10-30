import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.feature(
  .androidDevices,
  clients: [.androidEmulator, .androidPackage, .download, .preferences],
  shared: [.core]
)
