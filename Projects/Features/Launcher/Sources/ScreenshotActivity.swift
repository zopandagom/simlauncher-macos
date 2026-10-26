import Core

/// 기기별로 찍고 있는 스크린샷. 기기 작업(`DeviceActivity`)과 따로 두어 앱 설치·링크 열기 중에도 찍을 수 있다.
/// 이 화면이 지금 돌리는 작업(세션 상태)이라 Core 가 아니라 Feature 에 둔다. 기기만 보는 규칙은 Core 의 것을 부른다.
/// 바꾸는 메서드는 Model 만 부른다 (View 는 `model.screenshots` 를 읽기만 한다).
public struct ScreenshotActivity: Hashable, Sendable {
  public private(set) var deviceIDs: Set<VirtualDevice.ID> = []

  public init() {}

  public func isTaking(on id: VirtualDevice.ID) -> Bool {
    self.deviceIDs.contains(id)
  }

  /// 이 기기에서 찍고 있지 않고, `screenshotAvailability == .allowed` 이고, 같은 기기의 기기 작업이 없거나
  /// `.installApp`·`.openURL` 이면 true. 작업은 모든 케이스를 적는 허용 목록이다 (`default` 없음: 새 `DeviceTask` 케이스가
  /// 생기면 컴파일러가 여기서 멈춘다). `.boot` 는 켠 뒤에도 `bootButtonTapped` 가 다시 읽기가 끝날 때까지 쥐고 있어
  /// 그사이 목록 값이 켜짐일 수 있으므로 기기 규칙에 맡기지 않고 막는다.
  public func canStart(on device: VirtualDevice, during task: DeviceTask?) -> Bool {
    guard !self.isTaking(on: device.id), device.screenshotAvailability == .allowed else { return false }
    return switch task {
    case .none, .installApp, .openURL: true
    case .boot, .shutdown, .delete, .erase: false
    }
  }

  /// `canStart` 가 true 면 기록하고 true, 아니면 아무것도 바꾸지 않고 false.
  mutating func begin(on device: VirtualDevice, during task: DeviceTask?) -> Bool {
    guard self.canStart(on: device, during: task) else { return false }
    self.deviceIDs.insert(device.id)
    return true
  }

  /// 그 기기의 촬영 기록을 지운다. 없으면 아무것도 하지 않는다.
  mutating func end(on id: VirtualDevice.ID) {
    self.deviceIDs.remove(id)
  }
}
