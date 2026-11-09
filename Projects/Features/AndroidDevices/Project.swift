import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.feature(
  .androidDevices,
  clients: [.androidEmulator, .androidPackage, .appLog, .download, .preferences, .workspace],
  shared: [.core]
)
