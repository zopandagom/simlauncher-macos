import Core
import DevEnvironmentTesting
import Foundation
import SimulatorTesting
import Synchronization
import Testing
@testable import SetupFeature

/// Setup Model 테스트가 함께 쓰는 도움 함수. 테스트 타입이 채택하면 `Self.checkedModel()` 처럼 부른다.
@MainActor
protocol SetupModelTesting {}

@MainActor
extension SetupModelTesting {
  /// `status` 로 설정한 Fake 와 첫 확인까지 마친 Model. 런타임 이미지는 Simulator Fake 기본값
  /// (`RuntimeImage.samples`: 기본 iOS 27.1 이 Ready)이다.
  static func checkedModel(
    _ status: DevEnvironmentStatus,
    _ configure: (DevEnvironmentClientFake) -> Void = { _ in }
  ) async -> (SetupModel, DevEnvironmentClientFake) {
    let setup = await Self.runtimeModel(status) { devEnvironment, _ in configure(devEnvironment) }
    return (setup.model, setup.fake)
  }

  /// 두 Fake 를 설정하고 첫 확인까지 마친 Model. `sleeper` 를 주면 무진행 시계로 쓴다.
  static func runtimeModel(
    _ status: DevEnvironmentStatus = .ready(.sample),
    images: [RuntimeImage] = RuntimeImage.samples,
    sleeper: TestSleeper? = nil,
    _ configure: (DevEnvironmentClientFake, SimulatorClientFake) -> Void = { _, _ in }
  ) async -> SetupFixture {
    let fake = DevEnvironmentClientFake(status: status)
    let simulator = SimulatorClientFake()
    simulator.setRuntimeImages(images)
    configure(fake, simulator)
    let model = Self.makeModel(fake, simulator, sleeper: sleeper)
    await model.onAppear()
    return SetupFixture(model: model, fake: fake, simulator: simulator)
  }

  /// Xcode 준비됨이고 기본 iOS 가 없는(런타임 이미지 없음) Model. 첫 판정으로 끝난 뒤 기기 목록에서 Setup 을 다시 연 것처럼
  /// `reopened()` 를 불러 둔다 (설치 화면은 이렇게 다시 열었을 때 보인다).
  static func notInstalledModel(
    sleeper: TestSleeper? = nil,
    _ configure: (DevEnvironmentClientFake, SimulatorClientFake) -> Void = { _, _ in }
  ) async -> SetupFixture {
    let setup = await Self.runtimeModel(images: [], sleeper: sleeper, configure)
    setup.model.reopened()
    return setup
  }

  static func makeModel(
    _ fake: DevEnvironmentClientFake,
    _ simulator: SimulatorClientFake = SimulatorClientFake(),
    sleeper: TestSleeper? = nil
  ) -> SetupModel {
    guard let sleeper else {
      return SetupModel(devEnvironment: fake, simulator: simulator)
    }
    // MainActor 클로저로 넘겨, Model 의 시계 Task(MainActor)가 다른 실행기를 거치지 않고 곧바로 sleep 을 건다.
    return SetupModel(
      devEnvironment: fake,
      simulator: simulator,
      sleep: { @MainActor (duration: Duration) async throws in try await sleeper.sleep(duration) }
    )
  }

  static func installCount(in fake: DevEnvironmentClientFake) -> Int {
    fake.calls.filter { $0 == .installDefaultIOSRuntime }.count
  }

  static func fetchCount(in simulator: SimulatorClientFake) -> Int {
    simulator.calls.filter { $0 == .fetchRuntimeImages }.count
  }

  /// 설치를 띄우고 Fake 가 멈춰 재개를 기다릴 때까지 기다린다 (`suspendInstalls()` 를 먼저 부른다).
  static func startSuspendedInstall(_ model: SetupModel, _ fake: DevEnvironmentClientFake) async -> TrackedTask {
    let install = Self.start { await model.installRuntimeButtonTapped() }
    await Self.waitUntil { fake.suspendedInstallCount == 1 }
    return install
  }

  static func checkCount(in fake: DevEnvironmentClientFake) -> Int {
    fake.calls.filter { $0 == .checkEnvironment }.count
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

  /// 끝났는지 `waitUntil` 조건에서 볼 수 있게 작업을 띄운다. 회귀가 있으면 멈출 수 있는 호출(Fake 를 멈춘 동안의
  /// 이벤트)을 직접 await 하지 않고 이것으로 띄운다.
  static func start(_ operation: @escaping @MainActor () async -> Void) -> TrackedTask {
    TrackedTask(operation)
  }
}

/// 첫 확인까지 마친 Model 과 주입한 두 Fake.
@MainActor
struct SetupFixture {
  let model: SetupModel
  let fake: DevEnvironmentClientFake
  let simulator: SimulatorClientFake
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

/// 무진행 시계 대역. sleep 은 fireAll()·fireOldest() 까지 기다린다. sleep 은 MainActor 에서 돌아, 깨운 시계가
/// 다음 MainActor 차례에 끝난다 (테스트가 `Task.yield()` 로 기다릴 수 있다).
/// 기본: Task 가 취소되면 pending 에서 빼고 CancellationError 로 끝낸다.
/// ignoresCancellation: 취소돼도 pending 에 남고 fireAll()·fireOldest() 에 정상으로 깨어난다
/// (sleep 이 끝난 뒤 취소가 온 순서를 흉내).
final class TestSleeper: Sendable {
  private struct Waiter {
    let order: Int
    let duration: Duration
    let continuation: CheckedContinuation<Void, any Error>
  }

  private struct State {
    var waiters: [UUID: Waiter] = [:]
    var cancelledBeforeWait: Set<UUID> = []
    var nextOrder = 0
  }

  private let state = Mutex(State())
  let ignoresCancellation: Bool

  init(ignoresCancellation: Bool = false) {
    self.ignoresCancellation = ignoresCancellation
  }

  /// 지금 기다리는 sleep 의 길이 (걸린 순서대로).
  var pendingDurations: [Duration] {
    self.state.withLock { state in
      state.waiters.values.sorted { $0.order < $1.order }.map(\.duration)
    }
  }

  /// 취소 확인과 저장을 한 lock 안에서 한다 (`DevEnvironmentClientFake` 의 멈춘 설치와 같은 방식).
  /// ignoresCancellation 이면 취소 처리기는 아무것도 하지 않는다.
  @MainActor
  func sleep(_ duration: Duration) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        let cancelled: Bool = self.state.withLock { state in
          if state.cancelledBeforeWait.remove(id) != nil {
            return true
          }
          state.nextOrder += 1
          state.waiters[id] = Waiter(order: state.nextOrder, duration: duration, continuation: continuation)
          return false
        }
        if cancelled {
          continuation.resume(throwing: CancellationError())
        }
      }
    } onCancel: {
      guard !self.ignoresCancellation else { return }
      let waiter: Waiter? = self.state.withLock { state in
        guard let waiter = state.waiters.removeValue(forKey: id) else {
          state.cancelledBeforeWait.insert(id)
          return nil
        }
        return waiter
      }
      waiter?.continuation.resume(throwing: CancellationError())
    }
  }

  /// 기다리는 sleep 을 모두 정상으로 깨운다.
  func fireAll() {
    let waiters: [Waiter] = self.state.withLock { state in
      let waiters = Array(state.waiters.values)
      state.waiters = [:]
      return waiters
    }
    for waiter in waiters {
      waiter.continuation.resume()
    }
  }

  /// 가장 먼저 걸린 sleep 하나만 정상으로 깨운다.
  func fireOldest() {
    let waiter: Waiter? = self.state.withLock { state in
      guard let oldest = state.waiters.min(by: { $0.value.order < $1.value.order }) else { return nil }
      return state.waiters.removeValue(forKey: oldest.key)
    }
    waiter?.continuation.resume()
  }
}
