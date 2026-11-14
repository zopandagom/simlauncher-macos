import AndroidEmulatorInterface
import Core

/// 테스트 조건(`testConditions`·`setNightMode`·`setLocation`)의 Fake 동작과 설정 메서드.
/// 다른 앱 작업과 같이 목록·기기 상태를 보지 않고 설정한 결과만 돌려준다. 성공한 `setNightMode` 는 그 기기의 지금 값을 바꾼다.
public extension AndroidEmulatorClientFake {
  /// 테스트 조건 호출 (`Call.testCondition`).
  enum ConditionCall: Hashable, Sendable {
    case testConditions(AndroidVirtualDevice.ID)
    case setNightMode(DeviceAppearance, AndroidVirtualDevice.ID)
    case setLocation(GeoCoordinate, AndroidVirtualDevice.ID)
  }

  /// 설정하지 않은 기기의 값: 라이트, 위치 서비스 켜짐.
  static let defaultTestConditions = AndroidTestConditions(nightMode: .light, locationEnabled: true)

  /// 이 기기의 지금 값 (`testConditions(on:)` 이 돌려주고, 성공한 `setNightMode` 가 `nightMode` 를 바꾼다).
  func setTestConditions(_ conditions: AndroidTestConditions, for id: AndroidVirtualDevice.ID) {
    self.state.withLock { $0.conditions.values[id] = conditions }
  }

  /// 이 기기의 지금 값 (설정하지 않았으면 `defaultTestConditions`).
  func testConditions(for id: AndroidVirtualDevice.ID) -> AndroidTestConditions {
    self.state.withLock { $0.conditions.values[id] ?? Self.defaultTestConditions }
  }

  /// 설정하면 이후 `testConditions(on:)` 이 이 에러를 던진다.
  func setTestConditionsError(_ error: AndroidEmulatorError?) {
    self.state.withLock { $0.conditions.readError = error }
  }

  /// 이후 `setNightMode(_:on:)` 의 결과. nil(기본)이면 값을 바꾸고 `.applied`, `.success(.notApplied)` 면 값을 바꾸지 않는다.
  func setNightModeResult(_ result: Result<AndroidConditionOutcome, AndroidEmulatorError>?) {
    self.state.withLock { $0.conditions.nightModeResult = result }
  }

  /// 이후 `setLocation(_:on:)` 의 결과 (기본 `.success(.applied)`).
  func setLocationResult(_ result: Result<AndroidConditionOutcome, AndroidEmulatorError>) {
    self.state.withLock { $0.conditions.locationResult = result }
  }

  /// 이후 세 테스트 조건 호출이 기록만 하고 `resumeConditions()` 까지 기다린다.
  func suspendConditions() {
    self.suspend(.conditions)
  }

  /// 기다리는 테스트 조건 호출을 모두 깨우고, 이후 호출은 기다리지 않는다.
  func resumeConditions() {
    self.resume(.conditions)
  }

  /// 이후 읽기(`testConditions(on:)`)만 기록하고 `resumeConditionReads()` 까지 기다린다 (쓰기·위치는 기다리지 않는다).
  /// `suspendConditions()` 와 함께 걸면 둘 다 풀려야 돌아온다.
  func suspendConditionReads() {
    self.suspend(.conditionReads)
  }

  /// 기다리는 읽기를 모두 깨우고, 이후 읽기는 기다리지 않는다.
  func resumeConditionReads() {
    self.resume(.conditionReads)
  }

  /// 기록 → 멈춤(`.conditions` → 읽기 멈춤) → 지연 → 설정한 에러면 던짐 → 이 기기의 지금 값.
  func testConditions(on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) -> AndroidTestConditions {
    self.record(.testCondition(.testConditions(id)))
    await self.waitIfSuspended(.conditions)
    await self.waitIfSuspended(.conditionReads)
    await self.sleepIfNeeded()
    if let error = self.state.withLock({ $0.conditions.readError }) {
      throw error
    }
    return self.testConditions(for: id)
  }

  /// 기록 → 멈춤 → 지연 → 설정한 결과. 결과가 `.applied`(기본 포함)면 그 기기의 `nightMode` 를 요청 값으로 바꾼다.
  func setNightMode(
    _ appearance: DeviceAppearance,
    on id: AndroidVirtualDevice.ID
  ) async throws(AndroidEmulatorError) -> AndroidConditionOutcome {
    self.record(.testCondition(.setNightMode(appearance, id)))
    await self.waitIfSuspended(.conditions)
    await self.sleepIfNeeded()
    let result: Result<AndroidConditionOutcome, AndroidEmulatorError> = self.state.withLock { state in
      let result = state.conditions.nightModeResult ?? .success(.applied)
      if case .success(.applied) = result {
        var values = state.conditions.values[id] ?? Self.defaultTestConditions
        values.nightMode = appearance == .dark ? .dark : .light
        state.conditions.values[id] = values
      }
      return result
    }
    return try result.get()
  }

  /// 기록 → 멈춤 → 지연 → 설정한 결과. 위치는 저장하지 않는다 (실제로도 읽을 수 없다).
  func setLocation(
    _ coordinate: GeoCoordinate,
    on id: AndroidVirtualDevice.ID
  ) async throws(AndroidEmulatorError) -> AndroidConditionOutcome {
    self.record(.testCondition(.setLocation(coordinate, id)))
    await self.waitIfSuspended(.conditions)
    await self.sleepIfNeeded()
    return try self.state.withLock { $0.conditions.locationResult }.get()
  }
}

/// 테스트 조건 Fake 상태 (`AndroidEmulatorClientFake.State.conditions`).
struct AndroidConditionState {
  var values: [AndroidVirtualDevice.ID: AndroidTestConditions] = [:]
  var readError: AndroidEmulatorError?
  var nightModeResult: Result<AndroidConditionOutcome, AndroidEmulatorError>?
  var locationResult: Result<AndroidConditionOutcome, AndroidEmulatorError> = .success(.applied)
}
