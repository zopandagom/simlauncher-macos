/// 기기 작업(삭제·초기화)을 막는 이유.
public enum DeviceActionBlockReason: Hashable, Sendable {
  /// 꺼진 기기만 할 수 있다.
  case notShutdown
  /// 쓸 수 없는 기기는 초기화할 수 없다.
  case unavailable
}

/// 기기 작업을 지금 할 수 있는지.
public enum DeviceActionAvailability: Hashable, Sendable {
  case allowed
  case blocked(DeviceActionBlockReason)
}

/// 행별 허용 동작. Model 가드와 View(메뉴 비활성·이유)가 같은 규칙을 쓴다.
public extension VirtualDevice {
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
