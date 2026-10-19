import AppBundleTesting
import Core
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

/// Launcher Model 테스트가 함께 쓰는 도움 함수. 테스트 타입이 채택하면 `Self.loadedModel()` 처럼 부른다.
@MainActor
protocol LauncherModelTesting {}

@MainActor
extension LauncherModelTesting {
  /// 샘플 목록 Fake 를 설정하고 첫 목록까지 읽은 Model. 앱 번들 Fake 는 넘긴 것(기본: 샘플 앱)을 쓴다.
  static func loadedModel(
    appBundle: AppBundleClientFake = AppBundleClientFake(),
    _ configure: (SimulatorClientFake) -> Void = { _ in }
  ) async -> (LauncherModel, SimulatorClientFake) {
    let fake = SimulatorClientFake(inventory: .sample)
    configure(fake)
    let model = LauncherModel(simulator: fake, appBundle: appBundle)
    await model.onAppear()
    return (model, fake)
  }

  /// 샘플 목록에서 기기 하나의 상태만 바꾼 목록.
  static func inventory(_ id: VirtualDevice.ID, state: VirtualDevice.State) -> DeviceInventory {
    let sample = DeviceInventory.sample
    return DeviceInventory(
      devices: sample.devices.map { device in
        guard device.id == id else { return device }
        return VirtualDevice(
          id: device.id,
          name: device.name,
          family: device.family,
          state: state,
          availability: device.availability,
          runtime: device.runtime
        )
      },
      runtimes: sample.runtimes,
      deviceTypes: sample.deviceTypes
    )
  }

  /// 샘플 목록에서 기기 하나를 뺀 목록.
  static func inventory(removing id: VirtualDevice.ID) -> DeviceInventory {
    let sample = DeviceInventory.sample
    return DeviceInventory(
      devices: sample.devices.filter { $0.id != id },
      runtimes: sample.runtimes,
      deviceTypes: sample.deviceTypes
    )
  }

  /// 샘플 목록의 기기를 알림에 담을 값으로.
  static func label(_ id: VirtualDevice.ID) -> LauncherNotice.Device {
    let device = DeviceList(inventory: .sample).device(id: id)!
    return LauncherNotice.Device(name: device.name, runtimeName: device.runtime.name)
  }

  static func device(_ id: VirtualDevice.ID, in model: LauncherModel) -> VirtualDevice? {
    guard case let .loaded(list) = model.listState else { return nil }
    return list.device(id: id)
  }

  static func bootCount(_ id: VirtualDevice.ID, in fake: SimulatorClientFake) -> Int {
    fake.calls.filter { $0 == .boot(id) }.count
  }

  static func createCount(in fake: SimulatorClientFake) -> Int {
    fake.calls.filter {
      if case .create = $0 {
        true
      } else {
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

  /// 끝났는지 `waitUntil` 조건에서 볼 수 있게 작업을 띄운다. 회귀가 있으면 멈출 수 있는 호출(Fake 를 멈춘 동안의 두 번째
  /// 누름)을 직접 await 하지 않고 이것으로 띄운다.
  static func start(_ operation: @escaping @MainActor () async -> Void) -> TrackedTask {
    TrackedTask(operation)
  }
}

/// 기다리는 조건은 Fake 와 MainActor 의 차례 넘기기만으로 참이 되어, 정상이면 수 ms 안에 끝난다 (Launcher 스위트 전체가
/// 0.1초 안쪽). 느린 CI 에서 거짓 실패가 나지 않게 그 1000배 이상인 10초로 둔다.
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
