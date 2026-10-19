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
    case .deviceNotShutdown:
      String(
        localized: "켜져 있거나 상태가 바뀌는 중인 기기는 삭제하거나 초기화할 수 없습니다. 기기를 끈 뒤 다시 시도하세요.",
        bundle: .module
      )
    case .creationOptionUnavailable:
      String(
        localized: "고른 iOS 버전이나 기기 종류를 지금 사용할 수 없습니다. 목록을 새로 고친 뒤 다시 골라 주세요.",
        bundle: .module
      )
    case .invalidDeviceName:
      String(localized: "기기 이름은 1~100자로, 줄바꿈 같은 제어 문자 없이 입력하세요.", bundle: .module)
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
    case .creationResultUnknown:
      // simctl create 는 성공했지만 출력에서 UDID 를 읽지 못해 기기가 생겼을 수 있다.
      // 다시 만들면 같은 이름 기기가 하나 더 생기므로 목록부터 확인하게 한다.
      String(
        localized: """
        Xcode 가 알려 준 결과를 읽지 못해 기기가 만들어졌는지 확인하지 못했습니다. \
        기기가 만들어졌을 수 있으니 목록을 확인한 뒤, 없을 때만 다시 만드세요.
        """,
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
    case let .createFailed(device, .creationResultUnknown):
      // 만들기는 성공했지만 결과를 읽지 못한 경우라 실패로 단정하지 않는다 (본문이 목록 확인을 안내한다).
      String(localized: "“\(device.name)” (\(device.runtimeName)) 기기를 만들었는지 확인하지 못했습니다", bundle: .module)
    case let .createFailed(device, _):
      String(localized: "“\(device.name)” (\(device.runtimeName)) 기기를 만들지 못했습니다", bundle: .module)
    case let .deleteFailed(device, _):
      String(localized: "“\(device.name)” (\(device.runtimeName)) 기기를 삭제하지 못했습니다", bundle: .module)
    case let .eraseFailed(device, _):
      String(localized: "“\(device.name)” (\(device.runtimeName)) 기기를 초기화하지 못했습니다", bundle: .module)
    }
  }

  /// 알림 본문: 알림에 담긴 실패의 원인과 다음 할 일.
  static func message(for notice: LauncherNotice) -> String {
    switch notice {
    case let .refreshFailed(error),
         let .bootFailed(_, error),
         let .shutdownFailed(_, error),
         let .openAppFailed(_, error),
         let .createFailed(_, error),
         let .deleteFailed(_, error),
         let .eraseFailed(_, error):
      self.message(for: error)
    }
  }

  static var okButton: String {
    String(localized: "확인", bundle: .module)
  }

  // MARK: - 삭제·초기화 확인

  /// 확인 대화상자 제목. 확인할 것이 없으면 빈 문자열 (닫힌 대화상자가 읽는다).
  static func confirmationTitle(for confirmation: DeviceConfirmation?) -> String {
    guard let confirmation else { return "" }
    let device = confirmation.device
    return switch confirmation.action {
    case .delete:
      String(localized: "“\(device.name)” (\(device.runtimeName)) 기기를 삭제할까요?", bundle: .module)
    case .erase:
      String(localized: "“\(device.name)” (\(device.runtimeName)) 기기를 초기화할까요?", bundle: .module)
    }
  }

  static func confirmationMessage(for action: DeviceConfirmation.Action) -> String {
    switch action {
    case .delete:
      String(localized: "기기와 그 안의 앱·데이터가 모두 지워지며 되돌릴 수 없습니다.", bundle: .module)
    case .erase:
      String(localized: "기기에 설치한 앱과 데이터, 설정이 모두 지워지고 처음 상태로 돌아갑니다. 되돌릴 수 없습니다.", bundle: .module)
    }
  }

  static func confirmButton(for action: DeviceConfirmation.Action) -> String {
    switch action {
    case .delete:
      String(localized: "삭제", bundle: .module)
    case .erase:
      String(localized: "초기화", bundle: .module)
    }
  }

  static var cancelButton: String {
    String(localized: "취소", bundle: .module)
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

  static var deviceActionsMenu: String {
    String(localized: "기기 작업", bundle: .module)
  }

  static var eraseMenuItem: String {
    String(localized: "초기화…", bundle: .module)
  }

  static var deleteMenuItem: String {
    String(localized: "삭제…", bundle: .module)
  }

  /// 기기 작업 메뉴 항목이 막힌 이유.
  static func blockReason(_ reason: DeviceActionBlockReason) -> String {
    switch reason {
    case .notShutdown:
      String(localized: "삭제·초기화는 기기를 끈 뒤에 할 수 있습니다", bundle: .module)
    case .unavailable:
      String(localized: "사용할 수 없는 기기는 초기화할 수 없고 삭제만 할 수 있습니다", bundle: .module)
    }
  }

  // MARK: - 만들기

  static var createDeviceButton: String {
    String(localized: "기기 만들기", bundle: .module)
  }

  /// 만들 수 있는 기기 종류가 없을 때 툴바 + 버튼의 도움말 (`LauncherModel.isCreationUnavailable`).
  /// 원인이 런타임과 Xcode 버전 불일치면 다른 iOS 를 설치하는 것도 해결책이다.
  /// 3단계 런타임 설치 안내에서 문구를 함께 고친다.
  static var createUnavailableHelp: String {
    // 키가 한 줄 길이 제한을 넘어 줄 끝 `\` 로 이어 쓴다 (키는 한 줄이다).
    String(
      localized: """
      지금 이 Mac 에서 만들 수 있는 iPhone·iPad 기기 종류가 없습니다. iOS 가 설치되어 있는지 확인하고, \
      Xcode 를 최신 버전으로 업데이트하거나 한 번 실행해 준비를 마친 뒤 새로 고치세요.
      """,
      bundle: .module
    )
  }

  static var creatingLabel: String {
    String(localized: "기기를 만드는 중…", bundle: .module)
  }

  static var createSheetTitle: String {
    String(localized: "새 기기 만들기", bundle: .module)
  }

  static var nameField: String {
    String(localized: "이름", bundle: .module)
  }

  static var runtimePicker: String {
    String(localized: "iOS 버전", bundle: .module)
  }

  static var deviceTypePicker: String {
    String(localized: "기기 종류", bundle: .module)
  }

  static var createConfirmButton: String {
    String(localized: "만들기", bundle: .module)
  }

  /// 이름 입력란 아래에 보이는 문제. 100 은 `DeviceName.maxLength` 와 맞춘 고정 문구다 (바꾸면 함께).
  static func nameProblem(_ problem: DeviceNameProblem) -> String {
    switch problem {
    case .empty:
      String(localized: "이름을 입력하세요.", bundle: .module)
    case .tooLong:
      String(localized: "이름은 100자까지 입력할 수 있습니다.", bundle: .module)
    case .containsControlCharacter:
      String(localized: "이름에 줄바꿈이나 탭은 쓸 수 없습니다.", bundle: .module)
    }
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
    case .noCreatableDeviceType:
      String(localized: "만들 수 있는 iPhone·iPad 기기 종류가 없습니다", bundle: .module)
    case .noDevices:
      String(localized: "표시할 iPhone·iPad 시뮬레이터가 없습니다", bundle: .module)
    }
  }

  static func emptyMessage(for reason: DeviceListEmptyReason) -> String {
    switch reason {
    case .noIOSRuntime:
      // 3단계(Xcode·런타임 설치 안내)에서 바꾼다.
      String(localized: "Xcode 를 처음 실행할 때 나오는 안내에서 iOS 를 설치한 뒤 새로 고치세요.", bundle: .module)
    case .noCreatableDeviceType:
      String(
        localized: "설치된 iOS 버전으로 만들 수 있는 기기 종류를 찾지 못했습니다. Xcode 를 최신 버전으로 업데이트하거나 한 번 실행해 준비를 마친 뒤 새로 고치세요.",
        bundle: .module
      )
    case .noDevices:
      String(localized: "오른쪽 위 + 버튼이나 아래 버튼으로 iPhone·iPad 기기를 만드세요.", bundle: .module)
    }
  }
}
