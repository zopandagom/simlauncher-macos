import Foundation

/// 보일 Android 기기가 없을 때 그 이유. Android 도구가 준비되지 않은 경우는 Feature 가 따로 판단한다.
public enum AndroidDeviceListEmptyReason: Hashable, Sendable {
  case noDevices
}

/// 화면에 보이는 Android 기기 목록. 쓸 수 없는 기기도 보인다(비활성 + 이유). API 별 섹션은 두지 않는다 (행에 API 를 보인다).
public struct AndroidDeviceList: Hashable, Sendable {
  /// 표시 이름 순서(`localizedStandardCompare`), 같으면 AVD 이름.
  public let devices: [AndroidVirtualDevice]
  /// `devices` 가 비었을 때만 non-nil.
  public let emptyReason: AndroidDeviceListEmptyReason?

  public init(devices: [AndroidVirtualDevice]) {
    self.devices = devices.sorted(by: Self.deviceOrder)
    self.emptyReason = self.devices.isEmpty ? .noDevices : nil
  }

  public func device(id: AndroidVirtualDevice.ID) -> AndroidVirtualDevice? {
    self.devices.first { $0.id == id }
  }

  private static func deviceOrder(_ lhs: AndroidVirtualDevice, _ rhs: AndroidVirtualDevice) -> Bool {
    switch lhs.displayName.localizedStandardCompare(rhs.displayName) {
    case .orderedAscending: true
    case .orderedDescending: false
    case .orderedSame: lhs.id.rawValue < rhs.id.rawValue
    }
  }
}

/// 행별 허용 동작. Model 가드와 View(메뉴 비활성·이유)가 같은 규칙을 쓴다.
public extension AndroidVirtualDevice {
  /// 쓸 수 있고 꺼져 있을 때만 켤 수 있다.
  var canBoot: Bool {
    self.availability == .available && self.state == .shutdown
  }

  /// 켜는 중·켜짐이면 끌 수 있다 (쓸 수 없는 기기도. 앱 작업 중인지는 Feature 가 본다).
  var canShutdown: Bool {
    self.state != .shutdown
  }

  /// `.shutdown` 이면 allowed, 아니면 blocked(.notShutdown). 쓸 수 있는지는 보지 않는다.
  var deleteAvailability: DeviceActionAvailability {
    self.state == .shutdown ? .allowed : .blocked(.notShutdown)
  }

  /// 쓸 수 없으면 blocked(.unavailable) (상태보다 먼저), `.shutdown` 이 아니면 blocked(.notShutdown), 아니면 allowed.
  var eraseAvailability: DeviceActionAvailability {
    if self.availability != .available {
      return .blocked(.unavailable)
    }
    return self.state == .shutdown ? .allowed : .blocked(.notShutdown)
  }
}
