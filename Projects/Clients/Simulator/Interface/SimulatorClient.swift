import Core
import Foundation

/// iOS 시뮬레이터 기기·런타임·기기 종류와 런타임 디스크 이미지 목록을 읽고, 켜고 끄고, 만들고 지우고 초기화하고, 앱을 설치·실행하고 링크를 열고 화면을 찍고 녹화하는 Client.
/// Impl 은 `xcrun simctl` 과 같은 개발자 디렉터리를 쓴다. 쓸 Xcode 가 없으면(App 이 넘긴 provider 가 nil 을 돌려줌)
/// 어떤 명령도 실행하지 않고 `.developerToolsUnavailable` 를 던진다.
public protocol SimulatorClient: Sendable {
  /// 모든 플랫폼의 기기·런타임·기기 종류 목록 (`simctl list -j` 한 번). 화면용 필터는 `DeviceList` 가 한다.
  func fetchInventory() async throws(SimulatorError) -> DeviceInventory

  /// 런타임 디스크 이미지 목록 (`simctl runtime list -j` 한 번). 모든 플랫폼, 설치·삭제 중인 이미지도 상태와 함께.
  /// `fetchInventory()` 의 runtimes(`simctl list -j`)는 쓸 수 있는 런타임만 보이고 상태·build 가 없어 따로 둔다.
  /// 해석하지 못한 항목은 빼고, 최상위가 사전이 아니면 `.unexpectedOutput`. 네트워크를 쓰지 않는다.
  func fetchRuntimeImages() async throws(SimulatorError) -> [RuntimeImage]

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

  /// 켜진 기기 화면을 PNG 로 `file` 에 저장한다 (`simctl io <기기> screenshot --type=png --mask=ignored <경로>`, 사각 전체 화면).
  /// 있는 파일은 덮어쓴다 (호출한 쪽이 예약한 빈 파일). 실행 직전에 같은 개발자 디렉터리로 목록을 다시 읽어 없으면 `.deviceNotFound`,
  /// `.booted` 가 아니면 실행하지 않고 `.deviceNotBooted` (꺼진 기기에서는 simctl 이 약 60초 기다린 뒤 실패한다).
  /// 파일 URL 이 아니면 실행하지 않고 `.commandFailed`. 확인과 실행 사이에 꺼지는 드문 경우는 약 60초 뒤 `.deviceNotBooted`.
  func screenshot(on id: VirtualDevice.ID, to file: URL) async throws(SimulatorError)

  /// 켜진 기기 화면을 H.264 QuickTime 동영상으로 `file` 에 녹화한다
  /// (`simctl io <기기> recordVideo --codec=h264 --mask=ignored --force <경로>`, 사각 전체 화면, 소리 없음).
  /// **호출한 Task 의 취소가 멈춤이다**: 취소하면 SIGINT 로 멈추고 마무리를 기다린 뒤 돌아온다(취소는 실패가 아니다).
  /// 취소하지 않으면 simctl 이 스스로 끝날 때(시작 실패, 녹화 중 실패, 드물게 exit 0)까지 돌아오지 않는다
  /// (기기가 꺼져도 simctl 은 끝나지 않는다, 측정).
  /// 시작 신호(stderr `Recording started`)를 받으면 `onStarted` 를 한 번 부른다.
  /// 있는 파일은 덮어쓴다 (호출한 쪽이 예약한 빈 파일. 시작에 실패하면 지워져 있을 수 있다).
  /// 실행 직전에 같은 개발자 디렉터리로 목록을 다시 읽어 없으면 `.deviceNotFound`, `.booted` 가 아니면 실행하지 않고
  /// `.deviceNotBooted` (꺼진 기기에서 simctl 은 0바이트 파일을 남기고 성공한다, 측정). 파일 URL 이 아니면 실행하지 않고 `.commandFailed`.
  /// 같은 기기를 다른 녹화가 쓰고 있으면 `.recordingInProgress`. 스스로 끝났는데 파일이 비었거나 없으면 `.recordingEmpty`,
  /// 멈춘 뒤(시작 신호 뒤) 파일이 비었으면 `.recordingUnfinished`.
  func recordVideo(
    on id: VirtualDevice.ID,
    to file: URL,
    onStarted: @escaping @Sendable () async -> Void
  ) async throws(SimulatorError) -> ScreenRecordingResult
}

/// 화면 녹화의 끝.
public enum ScreenRecordingResult: Hashable, Sendable {
  /// 녹화한 화면을 파일에 저장했다 (크기 0 보다 큼).
  case saved
  /// simctl 이 스스로 실패(0 이 아닌 종료 코드)로 끝났지만 파일에 화면이 남았다 (크기 0 보다 큼). 끝난 데까지 저장됐다.
  /// 호출한 쪽은 파일을 지우지 않는다.
  case savedAfterFailure
  /// 시작 신호 전에 멈췄고(호출한 Task 취소) 저장된 화면이 없다. 파일은 비었거나 없다.
  case stoppedBeforeStart
}
