import Core

/// 기기 하나에서 진행 중인 작업. 같은 기기의 작업은 겹치지 않는다.
public enum DeviceTask: Hashable, Sendable {
  case boot, shutdown, delete, erase
  /// 앱 설치 흐름 전체 ((zip 이면 풀기 →) 검사 → 필요하면 켜기 → Simulator 앱 열기 → 설치 → 실행 → 다시 읽기
  /// (→ zip 이면 임시 폴더 정리)).
  case installApp
  /// 링크 열기 흐름 전체 (필요하면 켜기 → Simulator 앱 열기 → 링크 열기 → 다시 읽기).
  case openURL
}

/// 기기별 진행 작업과 "지금 이 기기에서 이 작업을 시작할 수 있나" 판정. Model 가드가 쓴다.
/// 이 화면이 지금 돌리는 작업(세션 상태)이라 Core 가 아니라 Feature 에 둔다. 기기만 보는 규칙은 Core 의 것을 부른다.
/// 바꾸는 메서드는 Model 만 부른다 (View 는 `model.activity` 를 읽기만 한다. 행은 `task(on:)` 로 진행 중 표시를 고른다).
public struct DeviceActivity: Hashable, Sendable {
  public private(set) var tasks: [VirtualDevice.ID: DeviceTask] = [:]

  public init() {}

  /// 작업이 진행 중인 기기.
  public var busyDeviceIDs: Set<VirtualDevice.ID> {
    Set(self.tasks.keys)
  }

  public func task(on id: VirtualDevice.ID) -> DeviceTask? {
    self.tasks[id]
  }

  /// 진행 중인 작업이 없고 기기 규칙이 허용하면 true. 기기 규칙: boot = 쓸 수 있고 `.shutdown`,
  /// shutdown = `.booted`, delete = `deleteAvailability == .allowed`, erase = `eraseAvailability == .allowed`,
  /// installApp·openURL = `appInstallAvailability == .allowed` (링크 열기도 설치와 같이 꺼져 있으면 켜고 연다).
  public func canStart(_ task: DeviceTask, on device: VirtualDevice) -> Bool {
    guard self.tasks[device.id] == nil else { return false }
    return switch task {
    case .boot: device.availability == .available && device.state == .shutdown
    case .shutdown: device.state == .booted
    case .delete: device.deleteAvailability == .allowed
    case .erase: device.eraseAvailability == .allowed
    case .installApp, .openURL: device.appInstallAvailability == .allowed
    }
  }

  /// `canStart` 가 true 면 기록하고 true, 아니면 아무것도 바꾸지 않고 false.
  mutating func begin(_ task: DeviceTask, on device: VirtualDevice) -> Bool {
    guard self.canStart(task, on: device) else { return false }
    self.tasks[device.id] = task
    return true
  }

  /// 그 기기의 작업 기록을 지운다. 없으면 아무것도 하지 않는다.
  mutating func end(on id: VirtualDevice.ID) {
    self.tasks[id] = nil
  }
}
