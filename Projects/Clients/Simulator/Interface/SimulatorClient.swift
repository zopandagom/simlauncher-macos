import Core

/// iOS 시뮬레이터 기기·런타임을 읽고, 켜고 끄고, 만들고 지우고 초기화하는 Client.
/// Impl 은 `xcrun simctl` 과 같은 개발자 디렉터리를 쓴다.
public protocol SimulatorClient: Sendable {
  /// 모든 플랫폼의 기기·런타임 목록 (`simctl list -j` 한 번). 화면용 필터는 `DeviceList` 가 한다.
  func fetchInventory() async throws(SimulatorError) -> DeviceInventory

  /// 기기를 켠다. 이미 켜졌거나 켜는 중이면 성공으로 본다.
  func boot(_ id: VirtualDevice.ID) async throws(SimulatorError)

  /// 기기를 끈다. 이미 꺼졌거나 끄는 중이면 성공으로 본다.
  func shutdown(_ id: VirtualDevice.ID) async throws(SimulatorError)

  /// 새 기기를 만들고 그 UDID 를 돌려준다. 이름은 `DeviceName.normalized` 값으로 만든다.
  /// 이름에 `DeviceName.problem` 이 있으면 `.invalidDeviceName`, 조합이 `DeviceCreationOptions`(실행 직전에 다시 읽은 목록)에
  /// 없으면 `.creationOptionUnavailable`. 같은 이름의 기기가 있어도 만든다.
  func create(
    name: String,
    deviceType: DeviceType.ID,
    runtime: DeviceRuntime.ID
  ) async throws(SimulatorError) -> VirtualDevice.ID

  /// 꺼진 기기를 지운다. 실행 직전에 목록을 다시 읽어 없으면 `.deviceNotFound`, 꺼져 있지 않으면 지우지 않고 `.deviceNotShutdown`.
  /// (`simctl delete` 는 켜진 기기도 끄고 지우므로 확인한다. 확인과 실행 사이에 켜지는 드문 경우는 막지 못한다.)
  func delete(_ id: VirtualDevice.ID) async throws(SimulatorError)

  /// 꺼진 기기의 앱·데이터·설정을 지워 처음 상태로 되돌린다 (`simctl erase`). 사전 확인은 `delete(_:)` 와 같다.
  func erase(_ id: VirtualDevice.ID) async throws(SimulatorError)

  /// simctl 과 같은 개발자 디렉터리의 Simulator 앱(Xcode 27.1 은 DeviceHub)을 연다.
  func openSimulatorApp() async throws(SimulatorError)
}
