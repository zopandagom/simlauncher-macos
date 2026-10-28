import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.feature(.androidSetup, clients: [.androidSDK, .preferences, .workspace], shared: [.core])
