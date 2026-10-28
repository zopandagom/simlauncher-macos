import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.feature(.settings, clients: [.preferences, .download, .androidSDK], shared: [.core])
