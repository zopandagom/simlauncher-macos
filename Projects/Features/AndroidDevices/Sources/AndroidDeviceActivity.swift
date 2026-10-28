import Core

/// 기기 하나에서 앱이 진행 중인 작업. 같은 기기의 작업은 겹치지 않는다.
public enum AndroidDeviceTask: Hashable, Sendable {
  /// 켜기 (emulator 를 띄우고 부팅 완료까지). 이 동안은 끄기를 막는다 (켜는 중에 끄면 기기가 망가질 수 있다, 실측).
  case boot
  case shutdown
  case delete
  case erase
}

/// 기기별 진행 작업과 "지금 이 기기에서 이 작업을 시작할 수 있나" 판정. Model 가드와 View(행의 진행 표시)가 쓴다.
/// 이 화면이 지금 돌리는 작업(세션 상태)이라 Core 가 아니라 Feature 에 둔다. 기기만 보는 규칙은 Core 의 것을 부른다.
/// iOS 기기 목록의 `DeviceActivity` 와 같은 규칙이지만 Feature 끼리 공유하지 않으므로 따로 둔다 (Android 는 받기 단계가 없다).
/// 바꾸는 메서드는 Model 만 부른다. 함께 켜기가 시작한 기록에는 소유자 번호를 붙여, 먼저 끝나 풀린 기기에 새로 시작한 작업을
/// 묶음의 끝이 지우지 않게 한다. 같음 비교는 기록만 본다 (다음 번호는 보지 않는다).
public struct AndroidDeviceActivity: Hashable, Sendable {
  public private(set) var tasks: [AndroidVirtualDevice.ID: AndroidDeviceTask] = [:]
  /// 함께 켜기가 시작한 기록의 소유자 번호. 한 기기 경로(`begin`)의 기록에는 없다.
  private var owners: [AndroidVirtualDevice.ID: Int] = [:]
  private var nextOwner = 0

  public init() {}

  /// 작업이 진행 중인 기기.
  public var busyDeviceIDs: Set<AndroidVirtualDevice.ID> {
    Set(self.tasks.keys)
  }

  public func task(on id: AndroidVirtualDevice.ID) -> AndroidDeviceTask? {
    self.tasks[id]
  }

  /// 진행 중인 작업이 없고 기기 규칙이 허용하면 true. 기기 규칙: boot = `canBoot`(쓸 수 있고 꺼짐),
  /// shutdown = `canShutdown`(켜는 중·켜짐. 앱이 켜는 중인 기기는 위의 작업 기록이 막는다),
  /// delete = `deleteAvailability == .allowed`, erase = `eraseAvailability == .allowed`.
  public func canStart(_ task: AndroidDeviceTask, on device: AndroidVirtualDevice) -> Bool {
    guard self.tasks[device.id] == nil else { return false }
    return switch task {
    case .boot: device.canBoot
    case .shutdown: device.canShutdown
    case .delete: device.deleteAvailability == .allowed
    case .erase: device.eraseAvailability == .allowed
    }
  }

  /// `canStart` 가 true 면 기록하고 true, 아니면 아무것도 바꾸지 않고 false.
  mutating func begin(_ task: AndroidDeviceTask, on device: AndroidVirtualDevice) -> Bool {
    guard self.canStart(task, on: device) else { return false }
    self.tasks[device.id] = task
    return true
  }

  /// 그 기기의 작업 기록과 소유자 번호를 지운다. 없으면 아무것도 하지 않는다.
  mutating func end(on id: AndroidVirtualDevice.ID) {
    self.tasks[id] = nil
    self.owners[id] = nil
  }

  /// `canStart(task, on:)` 가 true 인 기기만 시작하고, 시작한 기기에 새 소유자 번호를 붙인다 (기기가 없어도 번호를 돌려준다).
  /// 시작한 기기를 넘긴 순서로 돌려준다.
  mutating func beginAll(
    _ task: AndroidDeviceTask,
    on devices: [AndroidVirtualDevice]
  ) -> (begun: [AndroidVirtualDevice], owner: Int) {
    var begun: [AndroidVirtualDevice] = []
    for device in devices where self.begin(task, on: device) {
      begun.append(device)
    }
    self.nextOwner += 1
    for device in begun {
      self.owners[device.id] = self.nextOwner
    }
    return (begun, self.nextOwner)
  }

  /// 그 기기의 기록이 이 소유자 번호일 때만 지운다. 다르거나 없으면 아무것도 하지 않는다.
  mutating func end(on id: AndroidVirtualDevice.ID, owner: Int) {
    guard self.owners[id] == owner else { return }
    self.end(on: id)
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.tasks == rhs.tasks && lhs.owners == rhs.owners
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(self.tasks)
    hasher.combine(self.owners)
  }
}
