import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.feature(.update, clients: [.updateCheck, .preferences], shared: [.core])
