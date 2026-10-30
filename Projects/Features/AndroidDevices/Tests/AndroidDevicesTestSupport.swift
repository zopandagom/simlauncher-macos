import AndroidEmulatorInterface
import AndroidEmulatorTesting
import AndroidPackageTesting
import Core
import Foundation
import Synchronization
import Testing
@testable import AndroidDevicesFeature

/// AndroidDevices Model 테스트가 함께 쓰는 도움 함수. 테스트 타입이 채택하면 `Self.loadedFixture()` 처럼 부른다.
@MainActor
protocol AndroidDevicesTesting {}

@MainActor
extension AndroidDevicesTesting {
  /// Fake 를 설정하고 첫 읽기(`onAppear`)까지 마친 Model. 기본 목록은 `.sample` 이다.
  static func loadedFixture(
    _ inventory: AndroidDeviceInventory = .sample,
    _ configure: (AndroidEmulatorClientFake) -> Void = { _ in }
  ) async -> AndroidDevicesFixture {
    let fixture = Self.fixture(inventory, configure)
    await fixture.model.onAppear()
    return fixture
  }

  /// 아직 화면이 보이기 전(`onAppear` 전)의 Model. apk 검사 Fake 는 샘플 apk 를 돌려주고, 테스트가 `package` 로 바꾼다.
  static func fixture(
    _ inventory: AndroidDeviceInventory = .sample,
    _ configure: (AndroidEmulatorClientFake) -> Void = { _ in }
  ) -> AndroidDevicesFixture {
    let fake = AndroidEmulatorClientFake(inventory: inventory)
    configure(fake)
    let sleeper = ManualSleeper()
    let setupRequests = Counter()
    let package = AndroidPackageClientFake()
    let model = AndroidDevicesModel(
      emulator: fake,
      package: package,
      setupRequested: { setupRequests.increment() },
      sleep: { try await sleeper.sleep(for: $0) }
    )
    return AndroidDevicesFixture(
      model: model,
      fake: fake,
      package: package,
      sleeper: sleeper,
      setupRequests: setupRequests
    )
  }

  static func count(_ call: AndroidEmulatorClientFake.Call, in fake: AndroidEmulatorClientFake) -> Int {
    fake.calls.count(where: { $0 == call })
  }

  static func fetchCount(_ fake: AndroidEmulatorClientFake) -> Int {
    self.count(.fetchDevices, in: fake)
  }

  /// 지금 목록 (읽지 않았으면 실패를 기록하고 nil).
  static func list(
    _ model: AndroidDevicesModel,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> AndroidDeviceList? {
    guard case let .loaded(list) = model.listState else {
      Issue.record("목록을 읽지 않았다: \(model.listState)", sourceLocation: sourceLocation)
      return nil
    }
    return list
  }

  static func notices(_ model: AndroidDevicesModel) -> [AndroidDevicesNotice] {
    model.notices.map(\.notice)
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

  /// 일어나지 않아야 할 일이 일어날 틈을 준다 (MainActor 와 Fake 의 차례를 여러 번 넘긴다).
  static func settle() async {
    for _ in 0 ..< 50 {
      await Task.yield()
    }
  }

  /// 끝났는지 `waitUntil` 조건에서 볼 수 있게 작업을 띄운다.
  static func start(_ operation: @escaping @MainActor () async -> Void) -> TrackedTask {
    TrackedTask(operation)
  }
}

/// 첫 읽기까지 마친 Model 과 주입한 Fake·시계.
@MainActor
struct AndroidDevicesFixture {
  let model: AndroidDevicesModel
  let fake: AndroidEmulatorClientFake
  let package: AndroidPackageClientFake
  let sleeper: ManualSleeper
  let setupRequests: Counter
}

/// 기다리는 조건은 Fake 와 MainActor 의 차례 넘기기만으로 참이 되어 정상이면 수 ms 안에 끝난다.
/// 느린 CI 에서 거짓 실패가 나지 않게 10초로 둔다.
private let waitLimit: Duration = .seconds(10)

/// 테스트가 깨울 때까지 기다리는 `sleep`. 요청한 시간을 기록한다 (실제로 기다리지 않는다).
final class ManualSleeper: Sendable {
  private struct State {
    var requested: [Duration] = []
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state = Mutex(State())

  /// 요청된 기다림 (순서대로, 깨운 것 포함).
  var requested: [Duration] {
    self.state.withLock { $0.requested }
  }

  /// 아직 깨우지 않은 기다림 수.
  var pendingCount: Int {
    self.state.withLock { $0.waiters.count }
  }

  func sleep(for duration: Duration) async throws {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      self.state.withLock { state in
        state.requested.append(duration)
        state.waiters.append(continuation)
      }
    }
  }

  /// 기다리는 것을 모두 깨운다 (시간이 지난 것처럼).
  func resumeAll() {
    let waiters = self.state.withLock { state in
      let waiters = state.waiters
      state.waiters = []
      return waiters
    }
    for waiter in waiters {
      waiter.resume()
    }
  }
}

/// App 이 주입하는 클로저가 몇 번 불렸는지.
@MainActor
final class Counter {
  private(set) var value = 0

  func increment() {
    self.value += 1
  }
}

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

extension AndroidVirtualDevice {
  /// 같은 기기의 상태만 바꾼 값.
  func with(state: State) -> AndroidVirtualDevice {
    AndroidVirtualDevice(
      id: self.id,
      displayName: self.displayName,
      systemImage: self.systemImage,
      formFactor: self.formFactor,
      state: state,
      availability: self.availability
    )
  }

  /// 꺼진 휴대전화 하나 더 ("두 번째 폰", `Second_Phone`).
  static let secondPhoneSample = AndroidVirtualDevice(
    id: ID("Second_Phone"),
    displayName: "두 번째 폰",
    systemImage: .sample,
    formFactor: .phone,
    state: .shutdown,
    availability: .available
  )
}
