import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.client(.appLog, clients: [.simulator, .androidEmulator], shared: [.core])
