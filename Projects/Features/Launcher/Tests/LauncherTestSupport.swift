import Core
import SimulatorInterface
import SimulatorTesting
@testable import LauncherFeature

/// Launcher Model 테스트가 함께 쓰는 도움 함수. 테스트 타입이 채택하면 `Self.loadedModel()` 처럼 부른다.
@MainActor
protocol LauncherModelTesting {}

@MainActor
extension LauncherModelTesting {
  /// 샘플 목록 Fake 를 설정하고 첫 목록까지 읽은 Model.
  static func loadedModel(
    _ configure: (SimulatorClientFake) -> Void = { _ in }
  ) async -> (LauncherModel, SimulatorClientFake) {
    let fake = SimulatorClientFake(inventory: .sample)
    configure(fake)
    let model = LauncherModel(simulator: fake)
    await model.onAppear()
    return (model, fake)
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

  /// 조건이 참이 될 때까지 다른 작업에 차례를 넘긴다.
  static func waitUntil(_ condition: () -> Bool) async {
    while !condition() {
      await Task.yield()
    }
  }
}
