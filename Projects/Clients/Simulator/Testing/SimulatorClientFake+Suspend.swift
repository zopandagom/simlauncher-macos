import SimulatorInterface

// MARK: - 만들기·삭제·초기화 멈추기

public extension SimulatorClientFake {
  /// 이후 `create(name:deviceType:runtime:)` 가 기록만 하고 `resumeCreates()` 까지 기다린다.
  func suspendCreates() {
    self.suspend(.create)
  }

  /// 기다리는 `create(name:deviceType:runtime:)` 를 모두 깨우고, 이후 호출은 기다리지 않는다.
  func resumeCreates() {
    self.resume(.create)
  }

  /// 이후 `delete(_:)` 가 기록만 하고 `resumeDeletes()` 까지 기다린다.
  func suspendDeletes() {
    self.suspend(.delete)
  }

  /// 기다리는 `delete(_:)` 를 모두 깨우고, 이후 호출은 기다리지 않는다.
  func resumeDeletes() {
    self.resume(.delete)
  }

  /// 이후 `erase(_:)` 가 기록만 하고 `resumeErases()` 까지 기다린다.
  func suspendErases() {
    self.suspend(.erase)
  }

  /// 기다리는 `erase(_:)` 를 모두 깨우고, 이후 호출은 기다리지 않는다.
  func resumeErases() {
    self.resume(.erase)
  }
}
