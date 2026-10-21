import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.feature(.launcher, clients: [.simulator, .appBundle, .download], shared: [.core])
