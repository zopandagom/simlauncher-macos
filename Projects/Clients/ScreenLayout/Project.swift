import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.client(
  .screenLayout,
  clients: [.androidEmulator, .simulator, .devEnvironment, .command],
  shared: [.core]
)
