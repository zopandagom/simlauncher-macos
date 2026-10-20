import Core
import Foundation

/// iOS 시뮬레이터 기기·런타임·기기 종류를 읽고, 켜고 끄고, 만들고 지우고 초기화하고, 앱을 설치·실행하고 링크를 여는 Client.
/// Impl 은 `xcrun simctl` 과 같은 개발자 디렉터리를 쓴다.
public protocol SimulatorClient: Sendable {
  /// 모든 플랫폼의 기기·런타임·기기 종류 목록 (`simctl list -j` 한 번). 화면용 필터는 `DeviceList` 가 한다.
  func fetchInventory() async throws(SimulatorError) -> DeviceInventory

  /// 기기를 켠다. 이미 켜졌거나 켜는 중이면 성공으로 본다.
  func boot(_ id: VirtualDevice.ID) async throws(SimulatorError)

  /// 기기를 끈다. 이미 꺼졌거나 끄는 중이면 성공으로 본다.
  func shutdown(_ id: VirtualDevice.ID) async throws(SimulatorError)

  /// 새 기기를 만들고 그 UDID 를 돌려준다. 이름은 `DeviceName.normalized` 값으로 만든다.
  /// 이름에 `DeviceName.problem` 이 있으면 `.invalidDeviceName`, 조합이 `DeviceCreationOptions`(실행 직전에 다시 읽은 목록)에
  /// 없으면 `.creationOptionUnavailable`. 같은 이름의 기기가 있어도 만든다.
  /// 만든 뒤 출력에서 UDID 를 읽지 못하면 `.creationResultUnknown` (기기가 생겼을 수 있다).
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

  /// 켜진 기기에 .app 을 설치한다 (`simctl install`). 같은 번들 ID 가 있으면 덮어쓰고(실행 중이어도), 원본 파일은 고치지 않는다.
  /// 파일 URL 이 아니면 실행하지 않고 `.appNotFound`. 사전 목록 확인은 하지 않는다 (꺼져 있으면 simctl 이 `.deviceNotBooted`).
  func install(_ app: URL, on id: VirtualDevice.ID) async throws(SimulatorError)

  /// 설치된 앱을 실행한다 (`simctl launch`). 이미 실행 중이면 다시 띄운다(새 pid).
  /// 성공해도 앱이 곧바로 종료됐을 수 있다 (simctl 이 결정적으로 알려 주지 않는다).
  func launch(_ bundleID: AppBundleID, on id: VirtualDevice.ID) async throws(SimulatorError)

  /// 켜진 기기에서 링크를 연다 (`simctl openurl`). 사전 목록 확인·재조회는 하지 않는다 (꺼져 있으면 simctl 이 `.deviceNotBooted`).
  /// 처리할 앱이 없으면 `.urlNotHandled`, simctl 이 형식을 거절하면 `.invalidURL`.
  /// 성공은 기기에 열기 요청이 전달됐다는 뜻이고, 앱이 링크를 어떻게 처리했는지는 알 수 없다.
  /// 막 켠(콜드 부팅) 기기에서는 기기 준비가 끝날 때까지 돌아오지 않는다 (Xcode 27.1 에서 약 40초).
  func openURL(_ link: DeepLink, on id: VirtualDevice.ID) async throws(SimulatorError)
}
