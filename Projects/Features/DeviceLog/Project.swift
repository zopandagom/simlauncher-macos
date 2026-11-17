import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.feature(.deviceLog, clients: [.appLog, .preferences, .workspace], shared: [.core])
