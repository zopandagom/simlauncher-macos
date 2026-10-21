import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.feature(.setup, clients: [.devEnvironment, .simulator], shared: [.core])
