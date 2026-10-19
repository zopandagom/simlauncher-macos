import Foundation

/// 런타임 하나에 속한 화면 표시 기기 묶음.
public struct DeviceSection: Identifiable, Hashable, Sendable {
  public var id: DeviceRuntime.ID { self.runtime.id }
  public let runtime: DeviceRuntime
  public let devices: [VirtualDevice]

  public init(runtime: DeviceRuntime, devices: [VirtualDevice]) {
    self.runtime = runtime
    self.devices = devices
  }
}

/// 보일 기기가 없을 때 그 이유.
public enum DeviceListEmptyReason: Hashable, Sendable {
  /// 쓸 수 있는 iOS 런타임이 없고 보일 기기도 없다.
  case noIOSRuntime
  /// 쓸 수 있는 iOS 런타임은 있지만 보일 기기가 없다.
  case noDevices
}

/// 화면에 보이는 기기 목록. iOS 런타임 기기만 OS 별로 묶고 정렬한다.
public struct DeviceList: Hashable, Sendable {
  /// 버전 내림차순(같으면 런타임 이름) 섹션. 섹션 안은 phone → tablet → 그 밖, 다음 이름(숫자 인식) 순서.
  public let sections: [DeviceSection]
  /// `sections` 가 비었을 때만 non-nil.
  public let emptyReason: DeviceListEmptyReason?

  public init(inventory: DeviceInventory) {
    let listed = inventory.devices.filter(Self.isListed)
    let grouped = Dictionary(grouping: listed, by: \.runtime.id)
    self.sections = grouped.values
      .compactMap { devices -> DeviceSection? in
        guard let runtime = devices.first?.runtime else { return nil }
        return DeviceSection(runtime: runtime, devices: devices.sorted(by: Self.deviceOrder))
      }
      .sorted(by: Self.sectionOrder)
    if self.sections.isEmpty {
      let hasIOSRuntime = inventory.runtimes.contains { $0.platform == .iOS && $0.isAvailable }
      self.emptyReason = hasIOSRuntime ? .noDevices : .noIOSRuntime
    } else {
      self.emptyReason = nil
    }
  }

  /// Preview·테스트용. 묶기·정렬·빈 이유 규칙은 `init(inventory:)` 만 만든다.
  public init(sections: [DeviceSection], emptyReason: DeviceListEmptyReason?) {
    self.sections = sections
    self.emptyReason = emptyReason
  }

  /// 화면에 보이는 기기인지. iOS 런타임 기기면 쓸 수 없어도 보인다(비활성 + 이유).
  public static func isListed(_ device: VirtualDevice) -> Bool {
    device.runtime.platform == .iOS
  }

  public func device(id: VirtualDevice.ID) -> VirtualDevice? {
    for section in self.sections {
      if let device = section.devices.first(where: { $0.id == id }) {
        return device
      }
    }
    return nil
  }

  private static func sectionOrder(_ lhs: DeviceSection, _ rhs: DeviceSection) -> Bool {
    if lhs.runtime.version != rhs.runtime.version {
      return lhs.runtime.version > rhs.runtime.version
    }
    return self.nameOrder(lhs.runtime.name, rhs.runtime.name, tieBreak: (lhs.id.rawValue, rhs.id.rawValue))
  }

  private static func deviceOrder(_ lhs: VirtualDevice, _ rhs: VirtualDevice) -> Bool {
    let lhsRank = Self.familyRank(lhs.family)
    let rhsRank = Self.familyRank(rhs.family)
    if lhsRank != rhsRank {
      return lhsRank < rhsRank
    }
    return Self.nameOrder(lhs.name, rhs.name, tieBreak: (lhs.id.rawValue, rhs.id.rawValue))
  }

  private static func familyRank(_ family: VirtualDevice.Family) -> Int {
    switch family {
    case .phone: 0
    case .tablet: 1
    case .watch, .tv, .vision, .other: 2
    }
  }

  /// 이름이 같게 비교되면 식별자로 순서를 정해, 묶기(Dictionary) 순서와 무관하게 결과가 늘 같게 한다.
  private static func nameOrder(_ lhs: String, _ rhs: String, tieBreak: (String, String)) -> Bool {
    switch lhs.compare(rhs, options: [.numeric, .caseInsensitive]) {
    case .orderedAscending: true
    case .orderedDescending: false
    case .orderedSame: tieBreak.0 < tieBreak.1
    }
  }
}
