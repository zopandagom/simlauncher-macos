import Core
import Foundation
import PreferencesInterface
import PreferencesTesting
import Synchronization
import Testing
import UpdateCheckInterface
import UpdateCheckTesting
@testable import UpdateFeature

/// Update Model 테스트가 함께 쓰는 도움 함수. 테스트 타입이 채택하면 `Self.makeModel()` 처럼 부른다.
@MainActor
protocol UpdateModelTesting {}

@MainActor
extension UpdateModelTesting {
  /// 지금 버전 1.2.0, 시계 `clock`. Fake 기본 결과는 새 버전 1.3.0.
  static func makeModel(
    updateCheck: UpdateCheckClientFake = UpdateCheckClientFake(result: .success(v130)),
    preferences: PreferencesClientFake = PreferencesClientFake(),
    currentVersion: AppVersion? = v120,
    clock: TestClock = TestClock()
  ) -> UpdateModel {
    UpdateModel(
      updateCheck: updateCheck,
      preferences: preferences,
      currentVersion: currentVersion,
      now: { clock.now }
    )
  }

  /// `setLastUpdateCheck` 로 넘긴 시각들.
  static func recordedChecks(_ preferences: PreferencesClientFake) -> [Date] {
    preferences.calls.compactMap {
      if case let .setLastUpdateCheck(date) = $0 {
        date
      } else {
        nil
      }
    }
  }

  /// `setLatestKnownUpdateVersion` 으로 넘긴 값들 (nil = 지우기).
  static func recordedLatest(_ preferences: PreferencesClientFake) -> [String?] {
    preferences.calls.compactMap { call -> String?? in
      if case let .setLatestKnownUpdateVersion(version) = call {
        .some(version)
      } else {
        nil
      }
    }
  }

  /// Preferences 쓰기 호출 수 (자동 확인 설정·건너뛰기·기록·숨김·받은 최신 버전).
  static func writeCount(_ preferences: PreferencesClientFake) -> Int {
    preferences.calls.filter {
      switch $0 {
      case .setAutomaticUpdateCheck, .setSkippedUpdateVersion, .setLastUpdateCheck, .setUpdateBannerDismissal,
           .setLatestKnownUpdateVersion:
        true
      default:
        false
      }
    }.count
  }

  /// 조건이 참이 될 때까지 다른 작업에 차례를 넘긴다. `waitLimit` 안에 참이 되지 않으면 호출 지점에 실패를 기록하고
  /// 돌아온다 (회귀가 있어도 테스트가 멈추지 않고 실패로 끝나게).
  static func waitUntil(
    _ condition: () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    let deadline = ContinuousClock.now + waitLimit
    while !condition() {
      guard ContinuousClock.now < deadline else {
        Issue.record("\(waitLimit) 안에 조건이 참이 되지 않았다", sourceLocation: sourceLocation)
        return
      }
      await Task.yield()
    }
  }

  /// 끝났는지 `waitUntil` 조건에서 볼 수 있게 작업을 띄운다. 멈춘 Fake 를 기다리는 호출은 직접 await 하지 않고 이것으로 띄운다.
  static func start(_ operation: @escaping @MainActor () async -> Void) -> TrackedTask {
    TrackedTask(operation)
  }

  /// 멈춘 Fake 로 `operation` 을 띄우고, 요청이 Fake 에서 멈출 때까지 기다린다.
  static func startSuspended(
    _ updateCheck: UpdateCheckClientFake,
    calls: Int = 1,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ operation: @escaping @MainActor () async -> Void
  ) async -> TrackedTask {
    let task = TrackedTask(operation)
    await Self.waitUntil({ updateCheck.suspendedCallCount == calls }, sourceLocation: sourceLocation)
    return task
  }
}

/// 자동 확인 이벤트 두 가지. 같은 규칙을 둘 다에 확인할 때 쓴다.
enum AutomaticEvent: CaseIterable, Sendable, CustomTestStringConvertible {
  case launched
  case becameActive

  var testDescription: String {
    switch self {
    case .launched: "실행"
    case .becameActive: "활성화"
    }
  }

  @MainActor
  func send(to model: UpdateModel) async {
    switch self {
    case .launched:
      await model.appLaunched()
    case .becameActive:
      await model.appBecameActive()
    }
  }
}

let v110 = AppVersion("1.1.0")!
let v120 = AppVersion("1.2.0")!
let v130 = AppVersion("1.3.0")!
let v140 = AppVersion("1.4.0")!

/// 테스트가 바꾸는 시계. Model 의 `now` 가 읽는다.
final class TestClock: Sendable {
  static let start = Date(timeIntervalSince1970: 1_800_000_000)

  private let value: Mutex<Date>

  init(_ date: Date = TestClock.start) {
    self.value = Mutex(date)
  }

  var now: Date {
    self.value.withLock { $0 }
  }

  func advance(by interval: TimeInterval) {
    self.value.withLock { $0 = $0.addingTimeInterval(interval) }
  }

  func set(_ date: Date) {
    self.value.withLock { $0 = date }
  }
}

/// 기다리는 조건은 Fake 와 MainActor 의 차례 넘기기만으로 참이 되어 정상이면 수 ms 안에 끝난다.
/// 느린 CI 에서 거짓 실패가 나지 않게 10초로 둔다.
private let waitLimit: Duration = .seconds(10)

/// 끝났는지 볼 수 있는 작업.
@MainActor
final class TrackedTask {
  private(set) var isFinished = false
  private var task: Task<Void, Never>?

  init(_ operation: @escaping @MainActor () async -> Void) {
    self.task = Task {
      await operation()
      self.isFinished = true
    }
  }

  /// 작업이 끝날 때까지 기다린다.
  func value() async {
    await self.task?.value
  }
}

extension TimeInterval {
  static let hour: TimeInterval = 3600
  static let day: TimeInterval = 86400
}
