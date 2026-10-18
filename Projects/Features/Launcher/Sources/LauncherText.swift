import Core
import Foundation
import SimulatorInterface

/// 화면 문구. 모두 이 모듈의 `Localizable.xcstrings` 에서 찾는다 (`bundle: .module`).
/// 런타임·기기 이름은 여기를 거치지 않고 그대로(`Text(verbatim:)`) 보인다.
enum LauncherText {
  // MARK: - 오류 본문

  /// 원인과 다음 할 일. 명령 원문은 보이지 않는다.
  static func message(for error: SimulatorError) -> String {
    switch error {
    case .developerToolsUnavailable:
      String(
        localized: "Xcode 를 찾지 못했거나 아직 준비되지 않았습니다. Xcode 를 설치하고 한 번 실행해 준비를 마친 뒤 다시 시도하세요.",
        bundle: .module
      )
    case .deviceNotFound:
      String(localized: "이 기기를 더 이상 찾을 수 없습니다. 목록을 새로 고친 뒤 다른 기기를 골라 주세요.", bundle: .module)
    case .simulatorAppNotFound:
      String(
        localized: "이 Mac 의 Xcode 에서 Simulator 앱을 찾지 못했습니다. Xcode 를 최신 버전으로 업데이트하거나 다시 설치하세요.",
        bundle: .module
      )
    case .unexpectedOutput:
      String(
        localized: "Xcode 가 알려 준 기기 정보를 읽지 못했습니다. Xcode 를 최신 버전으로 업데이트한 뒤 다시 시도하세요.",
        bundle: .module
      )
    case .commandFailed:
      String(
        localized: "Xcode 를 한 번 실행해 라이선스 동의와 준비를 마쳤는지 확인한 뒤 다시 시도하세요. 계속 실패하면 Mac 을 재시동한 뒤 다시 시도하세요.",
        bundle: .module
      )
    }
  }

  // MARK: - 알림

  /// 알림 제목. 기기 작업 실패는 기기 이름과 런타임 이름을 넣어, 같은 원인으로 여러 기기가 실패해도 구별된다.
  /// 알림이 없으면 빈 문자열 (알림을 띄우기 전, 표시되지 않는 `.alert` 가 읽는다).
  static func title(for notice: LauncherNotice?) -> String {
    switch notice {
    case .none:
      ""
    case .refreshFailed:
      String(localized: "기기 목록을 새로 고치지 못했습니다", bundle: .module)
    case let .bootFailed(device, _):
      String(localized: "“\(device.name)” (\(device.runtimeName)) 기기를 켜지 못했습니다", bundle: .module)
    case let .shutdownFailed(device, _):
      String(localized: "“\(device.name)” (\(device.runtimeName)) 기기를 끄지 못했습니다", bundle: .module)
    case let .openAppFailed(device, _):
      String(
        localized: "“\(device.name)” (\(device.runtimeName)) 기기는 켜졌지만 Simulator 앱을 열지 못했습니다",
        bundle: .module
      )
    }
  }

  /// 알림 본문: 알림에 담긴 실패의 원인과 다음 할 일.
  static func message(for notice: LauncherNotice) -> String {
    switch notice {
    case let .refreshFailed(error),
         let .bootFailed(_, error),
         let .shutdownFailed(_, error),
         let .openAppFailed(_, error):
      self.message(for: error)
    }
  }

  static var okButton: String {
    String(localized: "확인", bundle: .module)
  }

  // MARK: - 기기 행

  static func reason(for reason: VirtualDevice.UnavailableReason) -> String {
    switch reason {
    case .runtimeNotInstalled:
      String(localized: "이 기기에 필요한 iOS 버전이 이 Mac 에 설치되어 있지 않아 사용할 수 없습니다.", bundle: .module)
    case .runtimeUnavailable:
      String(
        localized: "이 기기의 iOS 버전을 지금 사용할 수 없습니다. Xcode 를 한 번 실행해 준비를 마친 뒤 목록을 새로 고치세요.",
        bundle: .module
      )
    case .deviceTypeNotSupported:
      String(localized: "지금 Xcode 가 이 기기 모델을 지원하지 않아 사용할 수 없습니다.", bundle: .module)
    case .unknown:
      String(localized: "이 기기를 지금 사용할 수 없습니다. Xcode 를 한 번 실행해 준비를 마친 뒤 목록을 새로 고치세요.", bundle: .module)
    }
  }

  static var unavailableLabel: String {
    String(localized: "사용할 수 없음", bundle: .module)
  }

  static func stateLabel(for state: VirtualDevice.State) -> String {
    switch state {
    case .shutdown:
      String(localized: "꺼짐", bundle: .module)
    case .booted:
      String(localized: "켜짐", bundle: .module)
    case .booting:
      String(localized: "켜는 중", bundle: .module)
    case .shuttingDown:
      String(localized: "끄는 중", bundle: .module)
    case .unknown:
      String(localized: "상태 확인 중", bundle: .module)
    }
  }

  static var bootButton: String {
    String(localized: "켜기", bundle: .module)
  }

  static var shutdownButton: String {
    String(localized: "끄기", bundle: .module)
  }

  // MARK: - 목록 전체

  static var loading: String {
    String(localized: "기기 목록을 불러오는 중…", bundle: .module)
  }

  static var loadFailedTitle: String {
    String(localized: "기기 목록을 불러오지 못했습니다", bundle: .module)
  }

  static var refreshButton: String {
    String(localized: "새로 고침", bundle: .module)
  }

  static var retryButton: String {
    String(localized: "다시 시도", bundle: .module)
  }

  static func emptyTitle(for reason: DeviceListEmptyReason) -> String {
    switch reason {
    case .noIOSRuntime:
      String(localized: "iOS 시뮬레이터가 설치되어 있지 않습니다", bundle: .module)
    case .noDevices:
      String(localized: "표시할 iPhone·iPad 시뮬레이터가 없습니다", bundle: .module)
    }
  }

  static func emptyMessage(for reason: DeviceListEmptyReason) -> String {
    switch reason {
    case .noIOSRuntime:
      // 3단계(Xcode·런타임 설치 안내)에서 바꾼다.
      String(localized: "Xcode 를 처음 실행할 때 나오는 안내에서 iOS 를 설치한 뒤 새로 고치세요.", bundle: .module)
    case .noDevices:
      // 기기 만들기(1-B)에서 바꾼다.
      String(localized: "기기 만들기는 다음 업데이트에서 지원합니다.", bundle: .module)
    }
  }
}
