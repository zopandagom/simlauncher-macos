import Core
import SimulatorInterface

// MARK: - 테스트 조건 (화면 설정 읽기·쓰기, 위치)

public extension SimulatorClientFake {
  /// 테스트 조건 호출 (`Call.testCondition`).
  enum ConditionCall: Hashable, Sendable {
    case displaySettings(VirtualDevice.ID)
    case setDisplaySetting(IOSDisplaySetting, VirtualDevice.ID)
    case simulateLocation(IOSLocationSimulation, VirtualDevice.ID)
  }

  /// 설정하지 않은 기기의 화면 설정: 라이트·기본 글씨 크기(large)·고대비 끔.
  static let defaultDisplaySettings = IOSDisplaySettings(
    appearance: .value(.light),
    contentSize: .value(.large),
    increaseContrast: .value(false)
  )

  /// 이 기기의 지금 화면 설정 (`displaySettings(on:)` 이 돌려주고, 성공한 쓰기가 바꾼다).
  func setDisplaySettings(_ settings: IOSDisplaySettings, for id: VirtualDevice.ID) {
    self.state.withLock { $0.conditions.settings[id] = settings }
  }

  /// 이 기기의 지금 화면 설정 (설정하지 않았으면 `defaultDisplaySettings`).
  func displaySettings(for id: VirtualDevice.ID) -> IOSDisplaySettings {
    self.state.withLock { $0.conditions.settings[id] ?? Self.defaultDisplaySettings }
  }

  /// 설정하면 이후 `displaySettings(on:)` 이 이 에러를 던진다 (`setDisplaySetting` 의 다시 읽기는 이 에러를 보지 않는다).
  func setDisplaySettingsError(_ error: SimulatorError?) {
    self.state.withLock { $0.conditions.readError = error }
  }

  /// 설정하면 이후 `setDisplaySetting(_:on:)` 이 이 에러를 던진다 (값은 바꾸지 않는다).
  func setDisplaySettingError(_ error: SimulatorError?) {
    self.state.withLock { $0.conditions.writeError = error }
  }

  /// 설정하면 이후 `setDisplaySetting(_:on:)` 이 값을 바꾸지 않고 `.notApplied(이 값)` 을 돌려준다 (지금 값도 이 값으로 바꾼다:
  /// 실제처럼 다시 읽은 값이 지금 값이다). nil 이면 성공한다.
  func setDisplaySettingNotApplied(_ read: IOSDisplaySettings?) {
    self.state.withLock { $0.conditions.notAppliedRead = read }
  }

  /// 설정하면 이후 `simulateLocation(_:on:)` 이 이 에러를 던진다.
  func setLocationError(_ error: SimulatorError?) {
    self.state.withLock { $0.conditions.locationError = error }
  }

  /// true 면 이후 `.scenario` 시뮬레이션이 `.scenarioUnavailable` 를 돌려준다 (기본 false).
  func setScenarioUnavailable(_ unavailable: Bool) {
    self.state.withLock { $0.conditions.scenarioUnavailable = unavailable }
  }

  /// 이후 세 테스트 조건 호출이 기록만 하고 `resumeConditions()` 까지 기다린다.
  func suspendConditions() {
    self.suspend(.conditions)
  }

  /// 기다리는 테스트 조건 호출을 모두 깨우고, 이후 호출은 기다리지 않는다.
  func resumeConditions() {
    self.resume(.conditions)
  }

  /// 이후 읽기(`displaySettings(on:)`)만 기록하고 `resumeConditionReads()` 까지 기다린다 (쓰기·위치는 기다리지 않는다).
  /// `suspendConditions()` 와 함께 걸면 둘 다 풀려야 돌아온다.
  func suspendConditionReads() {
    self.suspend(.conditionReads)
  }

  /// 기다리는 읽기를 모두 깨우고, 이후 읽기는 기다리지 않는다.
  func resumeConditionReads() {
    self.resume(.conditionReads)
  }

  /// `install(_:on:)` 과 같은 순서로 기록·멈춤(`.conditions` → 읽기 멈춤)·지연·에러·기기 상태를 보고, 이 기기의 지금 값을 돌려준다.
  func displaySettings(on id: VirtualDevice.ID) async throws(SimulatorError) -> IOSDisplaySettings {
    self.record(.testCondition(.displaySettings(id)))
    await self.waitIfSuspended(.conditions)
    await self.waitIfSuspended(.conditionReads)
    await self.sleepIfNeeded()
    if let error = self.bootedDeviceError(id, configured: \.conditions.readError) {
      throw error
    }
    return self.displaySettings(for: id)
  }

  /// `install(_:on:)` 과 같은 순서로 기록·멈춤·지연·에러·기기 상태를 본다. `setDisplaySettingNotApplied` 값이 있으면 지금 값을 그것으로
  /// 바꾸고 `.notApplied(그 값)`, 없으면 그 항목을 요청 값으로 바꾸고 `.applied`.
  func setDisplaySetting(
    _ setting: IOSDisplaySetting,
    on id: VirtualDevice.ID
  ) async throws(SimulatorError) -> IOSDisplaySettingOutcome {
    self.record(.testCondition(.setDisplaySetting(setting, id)))
    await self.waitIfSuspended(.conditions)
    await self.sleepIfNeeded()
    if let error = self.bootedDeviceError(id, configured: \.conditions.writeError) {
      throw error
    }
    return self.state.withLock { state in
      if let read = state.conditions.notAppliedRead {
        state.conditions.settings[id] = read
        return .notApplied(read)
      }
      var settings = state.conditions.settings[id] ?? Self.defaultDisplaySettings
      switch setting {
      case let .appearance(value): settings.appearance = .value(value)
      case let .contentSize(value): settings.contentSize = .value(value)
      case let .increaseContrast(value): settings.increaseContrast = .value(value)
      }
      state.conditions.settings[id] = settings
      return .applied
    }
  }

  /// `install(_:on:)` 과 같은 순서로 기록·멈춤·지연·에러·기기 상태를 본다. 시나리오는 `setScenarioUnavailable(true)` 면
  /// `.scenarioUnavailable`, 그 밖은 `.applied`. 위치는 저장하지 않는다 (실제로도 읽을 수 없다).
  func simulateLocation(
    _ simulation: IOSLocationSimulation,
    on id: VirtualDevice.ID
  ) async throws(SimulatorError) -> IOSLocationOutcome {
    self.record(.testCondition(.simulateLocation(simulation, id)))
    await self.waitIfSuspended(.conditions)
    await self.sleepIfNeeded()
    if let error = self.bootedDeviceError(id, configured: \.conditions.locationError) {
      throw error
    }
    guard case .scenario = simulation, self.state.withLock({ $0.conditions.scenarioUnavailable }) else {
      return .applied
    }
    return .scenarioUnavailable
  }
}

/// 테스트 조건 Fake 상태 (`SimulatorClientFake.State.conditions`).
struct SimulatorConditionState {
  var settings: [VirtualDevice.ID: IOSDisplaySettings] = [:]
  var readError: SimulatorError?
  var writeError: SimulatorError?
  var notAppliedRead: IOSDisplaySettings?
  var locationError: SimulatorError?
  var scenarioUnavailable = false
}
