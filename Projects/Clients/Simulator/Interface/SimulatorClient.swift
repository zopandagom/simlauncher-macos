import Core
import Foundation

/// iOS 시뮬레이터 기기·런타임·기기 종류와 런타임 디스크 이미지 목록을 읽고, 켜고 끄고, 만들고 지우고 초기화하고, 설치된 앱·실행 중인 앱 목록을 읽고,
/// 앱을 설치·실행(콘솔을 붙인 실행 포함)·지우고 링크를 열고 화면을 찍고 녹화하고, 테스트 조건(외관·글씨 크기·고대비 읽기·쓰기,
/// 위치 한 점·경로·시나리오·지우기)을 바꾸는 Client.
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

  /// 켜진 기기에 사용자가 설치한 앱 목록 (`simctl listapps <기기>` 한 번, `ApplicationType` 이 `User` 인 항목만).
  /// 표시 이름(대소문자·숫자 자연 순서, `localizedStandardCompare`) → 번들 ID 순. 번들 ID 가 `AppBundleID` 형식이 아닌 항목은 뺀다.
  /// SimLauncher 레이아웃 러너(`IOSLayoutRunner.appBundleID`)는 뺀다 (다른 UI 테스트 러너는 그대로 보인다).
  /// 사전 목록 확인은 하지 않는다 (꺼진 기기는 simctl 이 SimError 405 → `.deviceNotBooted`, 없는 기기 "Invalid device" → `.deviceNotFound`).
  /// UDID 형식이 아니면 실행하지 않고 `.deviceNotFound`. 출력(OpenStep plist)의 최상위가 사전이 아니면 `.unexpectedOutput`. 기기를 바꾸지 않는다.
  func installedApps(on id: VirtualDevice.ID) async throws(SimulatorError) -> [InstalledApp]

  /// 켜진 기기에서 지금 떠 있는 앱의 번들 ID (`simctl spawn <기기> launchctl list` 의 `UIKitApplication:<번들 ID>[…]` 항목).
  /// 중복 없이 rawValue 오름차순. `AppBundleID` 형식이 아닌 항목과 SimLauncher 레이아웃 러너(`IOSLayoutRunner.appBundleID`)는 뺀다.
  /// SpringBoard 는 이 목록에 없다(실측). 사전 목록 확인은 하지 않는다 (꺼진 기기는 SimError 405 → `.deviceNotBooted`,
  /// 없는 기기 "Invalid device" → `.deviceNotFound`). UDID 형식이 아니면 실행하지 않고 `.deviceNotFound`.
  /// 출력이 UTF-8 이 아니면 `.unexpectedOutput`. 기기를 바꾸지 않는다.
  func runningApplications(on id: VirtualDevice.ID) async throws(SimulatorError) -> [AppBundleID]

  /// 켜진 기기에서 앱을 지운다 (`simctl uninstall <기기> <번들 ID>`). 설치돼 있지 않아도 성공(실측 exit 0). 실행 중이면 끝내고 지운다.
  /// 사전 목록 확인은 하지 않는다 (꺼진 기기는 SimError 405 → `.deviceNotBooted`, 실측 "Unable to lookup in current state: Shutdown",
  /// 없는 기기 "Invalid device" → `.deviceNotFound`). UDID 형식이 아니면 실행하지 않고 `.deviceNotFound`.
  /// 막 켠(부팅 중) 기기에서는 부팅이 끝날 때까지 돌아오지 않는다 (실측 약 38초).
  func uninstall(_ bundleID: AppBundleID, on id: VirtualDevice.ID) async throws(SimulatorError)

  /// 설치된 앱을 실행한다 (`simctl launch`). 이미 실행 중이면 다시 띄운다(새 pid).
  /// 성공해도 앱이 곧바로 종료됐을 수 있다 (simctl 이 결정적으로 알려 주지 않는다).
  func launch(_ bundleID: AppBundleID, on id: VirtualDevice.ID) async throws(SimulatorError)

  /// 설치된 앱을 콘솔을 붙여 실행하고(`simctl launch --console-pty --terminate-running-process <기기> <번들 ID>`),
  /// 끝날 때까지 앱 출력을 줄로 넘긴다. 앱의 stdout·stderr·NSLog 와 Logger(`OS_ACTIVITY_DT_MODE`)가 한 흐름으로 오고 구별하지 않는다.
  /// 이미 실행 중이면 그 앱을 끝내고 다시 띄운다. 사전 목록 확인은 하지 않는다 (꺼진 기기는 simctl 이 실패한다).
  /// - simctl 이 찍는 실행 신호 줄(`<번들 ID>: <pid>`, `\n` 으로 끝남)이나 **앱의 첫 줄** 중 먼저 온 것에서 `onEvent(.launched)` 를
  ///   한 번 부른다 (신호 줄은 앱의 첫 줄들보다 늦을 수 있고, 실패할 때 simctl 은 stdout 에 쓰지 않는다, 측정).
  ///   신호 줄과 simctl 이 끝에 찍는 빈 줄은 넘기지 않는다.
  /// - 앱 줄은 `onEvent(.lines(_:))` 로 받은 순서대로 넘긴다 (조각마다 다 된 줄만. 끝에 남은 조각은 끝날 때 한 줄로).
  ///   다음 조각은 앞 `onEvent` 가 끝난 뒤 넘긴다.
  /// - **호출한 Task 의 취소가 멈춤이다**: SIGINT(→ 10초 SIGTERM → 5초 SIGKILL)로 simctl 을 멈추고(SIGINT·SIGTERM 은 앱도 끝낸다)
  ///   끝나면 `.stopped` 로 돌아온다. 시간 제한은 없다.
  /// - 취소하지 않으면 앱이 끝나거나 기기가 꺼질 때 simctl 이 끝나고 `.exited` 로 돌아온다.
  /// - 신호 전에 0 이 아닌 코드로 끝나면 `launch(_:on:)` 와 같은 분류로 던진다 (`.appNotInstalled`·`.deviceNotBooted`·
  ///   `.appLaunchFailed`·`.commandFailed`). 신호 없이 0 으로 끝나면 `.exited` (실행은 된 것으로 본다). 신호 뒤에는 종료 코드와 관계없이 `.exited`.
  /// - UDID 형식이 아니면 실행하지 않고 `.deviceNotFound`. 쓸 Xcode 가 없거나 띄우지 못하면 `.developerToolsUnavailable`.
  /// - stdout 은 쌓지 않는다 (`CommandClient.streamCancellable`).
  func launchWithConsole(
    _ bundleID: AppBundleID,
    on id: VirtualDevice.ID,
    onEvent: @escaping @Sendable (AppConsoleEvent) async -> Void
  ) async throws(SimulatorError) -> AppConsoleEnd

  /// 켜진 기기에서 링크를 연다 (`simctl openurl`). 사전 목록 확인·재조회는 하지 않는다 (꺼져 있으면 simctl 이 `.deviceNotBooted`).
  /// 처리할 앱이 없으면 `.urlNotHandled`, simctl 이 형식을 거절하면 `.invalidURL`.
  /// 성공은 기기에 열기 요청이 전달됐다는 뜻이고, 앱이 링크를 어떻게 처리했는지는 알 수 없다.
  /// 막 켠(콜드 부팅) 기기에서는 기기 준비가 끝날 때까지 돌아오지 않는다 (Xcode 27.1 에서 약 40초).
  func openURL(_ link: DeepLink, on id: VirtualDevice.ID) async throws(SimulatorError)

  /// 켜진 기기 화면을 PNG 로 `file` 에 저장한다 (`simctl io <기기> screenshot --type=png --mask=ignored <경로>`, 사각 전체 화면).
  /// 화면이 둘인 기기에서 화면을 고르지 않아 실패하면(rc 22) `--display=primary` 를 붙여 한 번 더 실행한다.
  /// 있는 파일은 덮어쓴다 (호출한 쪽이 예약한 빈 파일). 실행 직전에 같은 개발자 디렉터리로 목록을 다시 읽어 없으면 `.deviceNotFound`,
  /// `.booted` 가 아니면 실행하지 않고 `.deviceNotBooted` (꺼진 기기에서는 simctl 이 약 60초 기다린 뒤 실패한다).
  /// 파일 URL 이 아니면 실행하지 않고 `.commandFailed`. 확인과 실행 사이에 꺼지는 드문 경우는 약 60초 뒤 `.deviceNotBooted`.
  func screenshot(on id: VirtualDevice.ID, to file: URL) async throws(SimulatorError)

  /// 켜진 기기 화면을 H.264 QuickTime 동영상으로 `file` 에 녹화한다
  /// (`simctl io <기기> recordVideo --codec=h264 --mask=ignored --force <경로>`, 사각 전체 화면, 소리 없음).
  /// 화면이 둘인 기기에서 화면을 고르지 않아 시작 전에 실패하면(rc 22) `--display=primary` 를 붙여 한 번 더 띄운다.
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

  /// 켜진 기기의 화면 설정 세 가지 (`simctl ui <기기> appearance`·`content_size`·`increase_contrast` 읽기를 차례로, provider 한 번).
  /// 각 줄은 앞뒤 공백을 빼고 대소문자를 무시해 해석한다: 알려진 값 → `.value`, `unsupported` → `.unsupported`, 그 밖 → `.unknown`.
  /// 꺼진 기기는 셋 다 exit 0 `unknown` 이라(실측) 셋이 모두 `.unknown` 이면 같은 디렉터리로 목록을 읽어 없으면 `.deviceNotFound`,
  /// 켜져 있지 않으면 `.deviceNotBooted` (켜져 있으면 셋 다 `.unknown` 그대로). 읽기가 0 이 아닌 종료 코드면
  /// SimError 405 → `.deviceNotBooted`, "Invalid device" → `.deviceNotFound`. UDID 형식이 아니면 실행하지 않고 `.deviceNotFound`.
  /// 기기를 바꾸지 않는다.
  func displaySettings(on id: VirtualDevice.ID) async throws(SimulatorError) -> IOSDisplaySettings

  /// 화면 설정 하나를 쓰고(`simctl ui <기기> appearance light|dark`·`content_size <토큰>`·`increase_contrast enabled|disabled`)
  /// 같은 디렉터리로 세 값을 다시 읽어 그 항목이 요청 값이면 `.applied`, 아니면 `.notApplied(읽은 값)`.
  /// simctl 은 잘못된 값에 exit 0 `Invalid argument` 를 찍기도 해서(실측) 종료 코드가 아니라 다시 읽은 값으로 판정한다.
  /// 쓰기가 0 이 아닌 종료 코드면 다시 읽지 않고 `displaySettings(on:)` 과 같이 분류해 던진다 (꺼진 기기 SimError 405).
  /// 실행 중 앱에 곧바로 반영되고 앱은 그대로이며, 기기를 껐다 켜도 남는다 (실측).
  func setDisplaySetting(_ setting: IOSDisplaySetting, on id: VirtualDevice.ID) async throws(SimulatorError)
    -> IOSDisplaySettingOutcome

  /// 기기 위치를 시뮬레이션한다 (`simctl location <기기> set|start|run|clear`). 좌표는 소수 6자리 `.` 소수점(로캘 무관).
  /// - point: `set <위도>,<경도>` (`--` 없음: set 은 `--` 를 좌표로 읽는다, 실측).
  /// - route: `start --speed=<m/s> -- <위도>,<경도>…` (`--` 필수: 음수 위도로 시작하는 경유지가 옵션으로 읽힌다, 실측).
  /// - scenario: 실행 전에 같은 디렉터리로 목록을 읽어 없으면 `.deviceNotFound`, 켜져 있지 않으면 `.deviceNotBooted`
  ///   (꺼진 기기에서 `run` 은 405 가 아니라 `Could not find scenario` 로 끝난다, 실측). `Could not find scenario` →
  /// `.scenarioUnavailable`.
  /// - clear: 진행 중인 경로·시나리오도 멈춘다.
  /// 0 이 아닌 종료 코드는 SimError 405 → `.deviceNotBooted`, "Invalid device" → `.deviceNotFound`, 그 밖 `.commandFailed`.
  /// 경로·시나리오는 simctl 이 끝난 뒤에도 기기 안에서 이어진다. 위치가 실제로 바뀌었는지는 읽을 방법이 없어 확인하지 않는다.
  func simulateLocation(_ simulation: IOSLocationSimulation, on id: VirtualDevice.ID) async throws(SimulatorError)
    -> IOSLocationOutcome
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
