import AndroidEmulatorInterface
import AppLogInterface

extension AppLogLaunchError {
  /// Android 실행 경로의 흔한 실패는 같은 뜻의 케이스로 옮기고, 그 밖(`appCommandFailed`·드문 사전 확인 실패·취소)은 `.commandFailed`.
  init(_ error: AndroidEmulatorError) {
    switch error {
    case .sdkUnavailable: self = .developerToolsUnavailable
    case .deviceNotFound: self = .deviceNotFound
    case let .deviceUnavailable(reason): self = .deviceUnavailable(reason)
    case .deviceNotBooted: self = .deviceNotBooted
    case .launchFailed(.notInstalled): self = .appNotInstalled
    case .launchFailed(.noLauncherActivity): self = .noLauncherActivity
    case .adbUnavailable: self = .adbUnavailable
    default: self = .commandFailed
    }
  }
}
