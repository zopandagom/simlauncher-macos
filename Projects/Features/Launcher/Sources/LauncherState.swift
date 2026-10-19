import AppBundleInterface
import Core
import SimulatorInterface

/// 기기 목록 화면의 상태.
public enum LauncherListState: Hashable, Sendable {
  /// 목록이 없고 읽는 중이다.
  case loading
  /// 읽은 목록. 다시 읽는 동안에도 마지막 목록을 유지한다.
  case loaded(DeviceList)
  /// 목록을 한 번도 읽지 못했다 (전체 화면 오류).
  case failed(SimulatorError)
}

/// 목록 위에 띄우는 알림. 기기 작업(켜기·끄기·만들기·삭제·초기화·앱 설치·실행) 실패와, 목록이 있을 때의 새로 고침 실패.
public enum LauncherNotice: Hashable, Sendable {
  /// 알림에 보일 기기. 누른 시점의 값이라, 실패 뒤 목록에서 사라져도 그대로 보인다.
  public struct Device: Hashable, Sendable {
    /// 기기 이름 (번역하지 않는 사용자 데이터).
    public let name: String
    /// 런타임 이름, 예 "iOS 26.0". OS 마다 같은 이름의 기기가 있어 함께 보인다.
    public let runtimeName: String

    public init(name: String, runtimeName: String) {
      self.name = name
      self.runtimeName = runtimeName
    }
  }

  case refreshFailed(SimulatorError)
  case bootFailed(Device, SimulatorError)
  case shutdownFailed(Device, SimulatorError)
  /// 기기는 켜졌지만 Simulator 앱을 열지 못했다.
  case openAppFailed(Device, SimulatorError)
  /// 기기를 만들지 못했다. Device 는 입력한(앞뒤 공백을 뺀) 이름과 고른 런타임 이름이다.
  case createFailed(Device, SimulatorError)
  case deleteFailed(Device, SimulatorError)
  case eraseFailed(Device, SimulatorError)
  /// 앱을 설치하지 못했다 (설치 명령 전 거절 포함). Device 는 누른 시점의 기기.
  case installFailed(Device, AppInstallFailure)
  /// 앱은 설치했지만 실행하지 못했다.
  case launchFailed(Device, SimulatorError)
}

/// 앱 설치 흐름의 실패 원인 (켜기·앱 열기 실패는 기존 bootFailed·openAppFailed 를 쓴다).
public enum AppInstallFailure: Hashable, Sendable {
  /// 끌어다 놓은 항목이 둘 이상이다.
  case multipleItems
  /// 번들 검사 실패.
  case bundle(AppBundleError)
  /// Core 판정 거절.
  case rejected(AppInstallProblem)
  /// 검사하는 사이 기기가 설치할 수 없는 상태가 됐다.
  case deviceNotReady(AppInstallBlockReason)
  /// install 명령 실패, 또는 검사하는 사이 기기가 목록에서 사라짐(`.deviceNotFound`).
  case simulator(SimulatorError)
}

/// 알림 한 건. 같은 내용이라도 쌓일 때마다 새 id 를 받는다 (View 가 다음 알림을 다시 띄우는 기준).
public struct LauncherNoticeItem: Identifiable, Hashable, Sendable {
  public let id: Int
  public let notice: LauncherNotice
}

/// 확인을 기다리는 삭제·초기화. 누른 시점의 기기 이름·런타임 이름을 담는다.
public struct DeviceConfirmation: Hashable, Sendable {
  public enum Action: Hashable, Sendable {
    case delete
    case erase
  }

  public let action: Action
  public let deviceID: VirtualDevice.ID
  public let device: LauncherNotice.Device

  public init(action: Action, deviceID: VirtualDevice.ID, device: LauncherNotice.Device) {
    self.action = action
    self.deviceID = deviceID
    self.device = device
  }
}

/// 확인 대화상자의 작업 규칙. Model 가드가 쓴다.
extension DeviceConfirmation.Action {
  var task: DeviceTask {
    switch self {
    case .delete: .delete
    case .erase: .erase
    }
  }

  func availability(for device: VirtualDevice) -> DeviceActionAvailability {
    switch self {
    case .delete: device.deleteAvailability
    case .erase: device.eraseAvailability
    }
  }
}

extension DeviceConfirmation {
  /// 이 확인의 작업이 실패했다는 알림.
  func failedNotice(_ error: SimulatorError) -> LauncherNotice {
    switch self.action {
    case .delete: .deleteFailed(self.device, error)
    case .erase: .eraseFailed(self.device, error)
    }
  }
}
