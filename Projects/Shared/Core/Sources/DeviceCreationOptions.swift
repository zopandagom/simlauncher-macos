import Foundation

/// 새 기기를 만들 때 고를 수 있는 런타임과 기기 종류.
/// Model(시트 기본값·선택 검증)과 Impl(실행 직전 재확인)이 같은 규칙을 쓴다.
public struct DeviceCreationOptions: Hashable, Sendable {
  /// 쓸 수 있는(isAvailable) iOS 런타임 중 iPhone·iPad 종류가 하나 이상인 것.
  /// 버전 내림차순, 같으면 이름(숫자 인식)·식별자 순서.
  public let runtimes: [DeviceRuntime]
  private let deviceTypesByRuntime: [DeviceRuntime.ID: [DeviceType]]

  public init(inventory: DeviceInventory) {
    let typesByID = Dictionary(inventory.deviceTypes.map { ($0.id, $0) }) { first, _ in first }
    var deviceTypesByRuntime: [DeviceRuntime.ID: [DeviceType]] = [:]
    for runtime in inventory.runtimes where runtime.platform == .iOS && runtime.isAvailable {
      let supported = runtime.supportedDeviceTypeIDs.compactMap { typesByID[$0] }
      // 같은 종류 안은 simctl 순서를 유지한다 (filter 는 안정적이다).
      let creatable = supported.filter { $0.family == .phone } + supported.filter { $0.family == .tablet }
      if !creatable.isEmpty {
        deviceTypesByRuntime[runtime.id] = creatable
      }
    }
    self.deviceTypesByRuntime = deviceTypesByRuntime
    self.runtimes = inventory.runtimes
      .filter { deviceTypesByRuntime[$0.id] != nil }
      .sorted(by: Self.runtimeOrder)
  }

  /// 최신 런타임 (`runtimes.first`).
  public var defaultRuntime: DeviceRuntime? {
    self.runtimes.first
  }

  public var isEmpty: Bool {
    self.runtimes.isEmpty
  }

  /// 그 런타임의 iPhone·iPad 종류. phone → tablet, 같은 종류 안은 `supportedDeviceTypeIDs` 순서.
  /// `inventory.deviceTypes` 에 없는 ID, phone·tablet 이 아닌 종류는 뺀다. 목록에 없는 런타임이면 [].
  public func deviceTypes(for runtimeID: DeviceRuntime.ID) -> [DeviceType] {
    self.deviceTypesByRuntime[runtimeID] ?? []
  }

  /// 그 런타임의 첫 기기 종류.
  public func defaultDeviceType(for runtimeID: DeviceRuntime.ID) -> DeviceType? {
    self.deviceTypes(for: runtimeID).first
  }

  /// 이 조합으로 만들 수 있는지.
  public func contains(runtime runtimeID: DeviceRuntime.ID, deviceType deviceTypeID: DeviceType.ID) -> Bool {
    self.deviceTypes(for: runtimeID).contains { $0.id == deviceTypeID }
  }

  private static func runtimeOrder(_ lhs: DeviceRuntime, _ rhs: DeviceRuntime) -> Bool {
    if lhs.version != rhs.version {
      return lhs.version > rhs.version
    }
    switch lhs.name.compare(rhs.name, options: [.numeric, .caseInsensitive]) {
    case .orderedAscending: return true
    case .orderedDescending: return false
    case .orderedSame: return lhs.id.rawValue < rhs.id.rawValue
    }
  }
}
