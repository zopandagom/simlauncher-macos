import Core

/// iOS 시뮬레이터 기기·런타임을 읽고 켜고 끄는 Client.
/// Impl 은 `xcrun simctl` 과 같은 개발자 디렉터리를 쓴다.
public protocol SimulatorClient: Sendable {
  /// 모든 플랫폼의 기기·런타임 목록 (`simctl list -j` 한 번). 화면용 필터는 `DeviceList` 가 한다.
  func fetchInventory() async throws(SimulatorError) -> DeviceInventory

  /// 기기를 켠다. 이미 켜졌거나 켜는 중이면 성공으로 본다.
  func boot(_ id: VirtualDevice.ID) async throws(SimulatorError)

  /// 기기를 끈다. 이미 꺼졌거나 끄는 중이면 성공으로 본다.
  func shutdown(_ id: VirtualDevice.ID) async throws(SimulatorError)

  /// simctl 과 같은 개발자 디렉터리의 Simulator 앱(Xcode 27.1 은 DeviceHub)을 연다.
  func openSimulatorApp() async throws(SimulatorError)
}
