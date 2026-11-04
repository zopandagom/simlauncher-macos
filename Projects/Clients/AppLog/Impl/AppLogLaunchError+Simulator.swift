import AppLogInterface
import SimulatorInterface

extension AppLogLaunchError {
  /// 같은 이름 6개는 1:1, 그 밖은 `.commandFailed`.
  init(_ error: SimulatorError) {
    switch error {
    case .developerToolsUnavailable: self = .developerToolsUnavailable
    case .deviceNotFound: self = .deviceNotFound
    case .deviceNotBooted: self = .deviceNotBooted
    case .appNotInstalled: self = .appNotInstalled
    case .appLaunchFailed: self = .appLaunchFailed
    case .commandFailed: self = .commandFailed
    default: self = .commandFailed
    }
  }
}
