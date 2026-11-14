import Core
import Foundation

/// Android 기기(AVD) 목록·상태와 켜기·끄기·만들기·삭제·초기화, 켜진 기기에 apk 설치·앱 실행(logcat 받기)·링크 열기·스크린샷·녹화·
/// 화면 레이아웃 읽기, 테스트 조건(외관 읽기·쓰기, 위치 한 점, 위치 서비스 켜짐 읽기).
/// AVD 폴더는 `$HOME/.android/avd` (Android Studio 와 함께 쓴다. ANDROID_AVD_HOME 은 보지 않는다).
/// SDK 위치는 App 이 주입한 provider 를 공개 메서드 한 번에 한 번 부른다. 명령은 CommandClient 로
/// `<SDK>/emulator/emulator` 와 `<SDK>/platform-tools/adb` 만 실행한다. 네트워크 API 를 쓰지 않는다
/// (에뮬레이터 자체의 Google 접속은 ARCHITECTURE §4 네트워크 행).
public protocol AndroidEmulatorClient: Sendable {
  /// AVD 목록과 만들기 선택지. 파일을 읽고, 실행 중인 AVD 가 있을 때만 adb 를 부른다 (없으면 명령 없음).
  /// 메인 밖에서 돈다. SDK 위치를 쓸 수 없거나 emulator·platform-tools 실행 파일이 없으면 실패하지 않고 `sdkAvailable == false` 인
  /// 목록을 돌려준다: adb 를 부르지 않고 잠금만으로 상태를 정하며(잠금 = 켜짐), 모든 기기는 `.unavailable(.sdkUnavailable)`,
  /// 만들기 선택지는 비어 있다. `.sdkUnavailable` 을 던지지 않는다.
  /// `avd` 폴더가 없으면 빈 목록(만들지 않는다), 있는데 읽지 못하면 `.avdFolderUnavailable`.
  /// adb 가 실패하면 실행 중인 기기를 켜짐으로 보고 실패로 돌려주지 않는다.
  func fetchDevices() async throws(AndroidEmulatorError) -> AndroidDeviceInventory

  /// 켠다: 실행 직전에 다시 읽어 없으면 `.deviceNotFound`, 쓸 수 없으면 `.deviceUnavailable`.
  /// 이미 실행 중(잠금)이면 띄우지 않고 완료를 기다린다. 아니면 `adb devices` 를 한 번 부른 뒤(adb 가 먼저
  /// `~/.android/adbkey` 를 0600 으로 만들게. 실패는 무시) emulator 를 띄우고(`launch`)
  /// `sys.boot_completed=1` 까지 1초 간격으로 확인한다. 완료 전에 프로세스가 끝나면 `.emulatorExited`,
  /// 10분이 지나면 `.bootTimedOut` (에뮬레이터는 끄지 않는다). 띄우지 않고 기다리는 중 잠금이 풀리고 앱 프로세스도 없으면
  /// `.emulatorExited(nil)`. Task 취소는 기다림만 멈추고 `.cancelled` (끄지 않는다).
  func boot(_ id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError)

  /// 끈다: 꺼져 있으면 성공. adb 로 그 AVD 의 serial 을 찾아 `emu kill`, serial 이 없고 이 앱이 띄운 프로세스면 SIGINT.
  /// 잠금이 풀릴 때(또는 이 앱이 띄운 프로세스가 끝날 때)까지 최대 150초 기다리고, 넘으면 `.shutdownTimedOut`.
  /// serial 도 프로세스도 없으면 10초 동안 1초 간격으로 다시 찾는다(앱 밖에서 막 켜 adb 에 아직 안 보이는 경우). 그래도 없을 때
  /// adb 가 답했으면 같은 150초까지 잠금 풀림을 기다리고(앱 밖에서 끄는 중이면 저장이 끝날 때까지 콘솔이 이름에 답하지 않는다),
  /// adb 가 답하지 않으면 `.adbUnavailable`. `emu kill` 이 실패하고 이 앱이 띄운 프로세스가 없으면, 잠금이 풀렸거나 잠금이 잡힌 채
  /// 그 기기가 이름에 답하지 않을 때는 기다리고, 아니면(잠금을 알 수 없을 때 포함) `.adbUnavailable`.
  func shutdown(_ id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError)

  /// 새 AVD 를 만들고 그 이름을 돌려준다. 표시 이름에 `DeviceName.problem` 이 있으면 `.invalidDeviceName`.
  /// 실행 직전에 다시 읽은 선택지에 이미지·프로필이 없거나, 폴더블인데 그 이미지에 접기 설정 파일이 없으면
  /// `.creationOptionUnavailable`.
  /// AVD 이름은 `AndroidAVDName.make` (다시 읽은 목록 기준). 폴더·ini 를 덮어쓰지 않는다(독점 생성).
  func create(
    displayName: String,
    image: AndroidSystemImageRef,
    profile: AndroidDeviceProfile.ID
  ) async throws(AndroidEmulatorError) -> AndroidVirtualDevice.ID

  /// 꺼진 AVD 를 지운다. SDK 를 쓸 수 없으면 adb 없이 잠금만으로 실행 중을 확인해 지운다 (목록 읽기와 같다).
  /// 실행 직전에 다시 읽은 폴더 목록에서 `<id>.ini` 항목을 찾아(이름으로 경로를 만들지 않는다)
  /// 없으면 `.deviceNotFound`, 잠금·adb 로 다시 확인해 실행 중이면 `.deviceRunning`.
  /// `path` 가 `.avd` 로 끝나는 실제 디렉터리(링크 아님)일 때만 폴더를 지우고, 아니면 ini 만 지운 뒤 `.folderKept(path)` 를 돌려준다.
  func delete(_ id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) -> AndroidDeleteOutcome

  /// 꺼진 AVD 의 사용자 데이터·스냅샷을 지운다 (`AndroidAVDReset`, 링크는 따라가지 않고 링크만 지운다). 켜지 않는다.
  /// 사전 확인은 `delete` 와 같고, SDK 를 쓸 수 없으면 `.sdkUnavailable`. 쓸 수 없는 기기는 `.deviceUnavailable`.
  /// 기기 폴더가 링크이거나 `.avd` 로 끝나지 않으면 `.unsafeDeviceFolder` (아무것도 지우지 않는다).
  func erase(_ id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError)

  /// 켜진 기기의 API 수준·ABI (`getprop ro.build.version.sdk`·`ro.product.cpu.abilist`). 메인 밖에서 돈다.
  /// 실행 직전에 다시 읽어 없으면 `.deviceNotFound`, 쓸 수 없으면 `.deviceUnavailable`, 잠금은 있는데 adb 가 답하지 않으면
  /// `.adbUnavailable`, 켜짐(`sys.boot_completed=1`)이 아니면 `.deviceNotBooted` (SDK 확인은 다른 메서드와 같다).
  /// 이 사전 확인은 아래 앱 작업 메서드 모두 같다. 값을 읽지 못하면(빈 값·숫자 아님) `.deviceNotBooted`.
  func deviceTraits(_ id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) -> AndroidDeviceTraits

  /// apk 를 설치한다: `adb -s <serial> install -r -t -d --no-incremental <apk>` (최대 10분, 넘으면 `.installTimedOut`).
  /// 실패 출력의 `Failure [<코드>` 를 `.installFailed(_)` 로, 켜는 중·끊김 출력은 `.deviceNotBooted` 로 바꾼다.
  /// `apk` 는 `AndroidPackageClient.inspect` 가 돌려준 `location` (절대 경로, 확장자 .apk) 이어야 한다 (adb 는 .apk 로 끝나지 않으면 거절).
  func install(_ apk: URL, on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError)

  /// 패키지의 launcher 화면을 찾고(`installedPackages` 와 같은 사전 확인 뒤 `cmd package resolve-activity` → 기기가 하나로 고르지 못하면
  /// (launcher 가 둘 이상) `cmd package query-activities` 의 첫 화면, 없으면 `pm path` 로 `.launchFailed(.notInstalled)`·
  /// `.launchFailed(.noLauncherActivity)`), 앱을 끄고(`am force-stop`, 떠 있지 않아도 성공) 기기 시각을 읽은 뒤(`date +%s.%N`)
  /// `am start -n` 으로 새로 실행하고, 메인 프로세스 pid(`pidof <패키지>`, 기기 안에서 0.1초 간격 60번, 명령 하나 30초 제한이며
  /// 넘으면 `.adbUnavailable`)를 얻으면 `.launched` 를 한 번 부르고 `logcat --pid=<pid> -v threadtime -T <시각>` 의 줄을 넘긴다
  /// (실행 직후 줄부터).
  /// **돌아오는 때**: 앱 프로세스가 끝나면 약 1초 뒤 `.appExited`, 그 전에 adb 가 끝나면(기기 꺼짐·adb 끊김) `.connectionLost`,
  /// 호출한 Task 가 취소되면 SIGINT 로 멈춘 뒤 `.stopped` (앱은 끄지 않는다. `.launched` 전 취소면 부르지 않았다). 취소는 던지지 않는다.
  /// pid 를 얻기 전에 앱이 끝났으면 그 앱 uid 의 실행 뒤 줄을 한 번 읽어(`logcat -d --uid`) `.launched`·줄을 넘기고 `.appExited`
  /// (uid·줄을 읽지 못하면 `.launched` 뒤 줄 없이 `.connectionLost`). 던지는 것은 `.launched` 전 실패뿐이다.
  /// 다른 프로세스(`android:process`)의 줄은 받지 않는다. 버퍼 머리 줄(`--------- …`)은 넘기지 않는다. stdout 은 쌓지 않는다.
  func launchWithLogcat(
    _ package: AndroidPackageName,
    on id: AndroidVirtualDevice.ID,
    onEvent: @escaping @Sendable (AndroidLogcatEvent) async -> Void
  ) async throws(AndroidEmulatorError) -> AndroidLogcatEnd

  /// `am start -a android.intent.action.VIEW -d <링크>` (링크는 원격 셸용으로 작은따옴표 인용). 받을 앱이 없으면 `.urlNotHandled`.
  func openURL(_ link: DeepLink, on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError)

  /// 사용자가 설치한 앱(`pm list packages -3`)의 패키지 이름, 이름순. 형식에 맞지 않는 줄은 건너뛴다.
  func installedPackages(on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) -> [AndroidPackageName]

  /// 켜진 기기 화면을 PNG 로 `file`(Workspace 가 예약한 빈 파일)에 쓴다 (`adb -s <serial> exec-out 'screencap -p 2>/dev/null'`,
  /// 30초 제한). 화면이 여럿인 기기(폴더블)는 지금 보이는 화면을 찍는다(실측). 사전 확인은 앱 작업과 같다. 종료 코드 ≠ 0·출력이 PNG 가 아님·시간 초과는 `.captureFailed`,
  /// 파일에 쓰지 못하면(파일 없음·링크·일반 파일 아님·디스크) `.captureFileUnwritable` (일부만 썼으면 0바이트로 자른다).
  /// 화면이 꺼져 있으면 검은 화면이 저장된다(휴대전화·폴더블 실측. 폴더블은 대개 지금 보이는 쪽 크기의 검은 화면이고, 접힌 직후에는 펼친 크기인 경우가 있었다).
  func screenshot(on id: AndroidVirtualDevice.ID, to file: URL) async throws(AndroidEmulatorError)

  /// 켜진 기기 화면을 H.264 mp4 로 기기 임시 파일(`/data/local/tmp/simlauncher-recording-<UUID>.mp4`)에 녹화한 뒤
  /// `file`(예약한 빈 파일)로 가져온다(`adb pull`). **호출한 Task 의 취소가 멈춤이다**: 기기 안 screenrecord 에 `kill -2 <pid>` 를
  /// 보내 마무리를 기다린 뒤 가져오고 돌아온다 (취소는 실패가 아니다. 멈춘 뒤의 명령은 취소를 물려받지 않는다).
  /// 녹화 adb 프로세스가 끝나기 전에는 돌아오지 않는다. 시작 신호(셸 pid 줄)를 받으면 `onStarted` 를 한 번(돌아오기 전에만) 부른다.
  /// 시작 전에 이미 취소됐으면 `.stoppedBeforeStart`. API 34 이상은 `--time-limit 0`(제한 없음), 그 아래는 기본 180초.
  /// 사전 확인은 앱 작업과 같다. 시작 전에 이 앱이 남긴 기기 임시 파일(`simlauncher-recording-*.mp4`)을 지운다. 끝난 녹화의 기기 임시
  /// 파일은 가져왔거나 화면이 없을 때만 지우고, 화면이 담긴 파일을 가져오지 못했으면(`.captureFileUnwritable`·`.recordingLost`·
  /// `.recordingTransferTimedOut`) 기기에 남긴다(그 기기에서 다음 녹화를 시작할 때 지운다).
  /// 가져오지 못하면 `file` 은 0바이트로 남긴다(호출한 쪽이 지운다).
  /// 화면이 꺼진(잠든) 기기에서 스스로 실패로 끝나 화면이 없으면 `.recordingDisplayOff` (화면이 여럿인 기기 실측).
  func recordScreen(
    on id: AndroidVirtualDevice.ID,
    to file: URL,
    onStarted: @escaping @Sendable () async -> Void
  ) async throws(AndroidEmulatorError) -> AndroidScreenRecordingResult

  /// 켜진 기기의 화면 레이아웃: 사전 확인(앱 작업과 같다) → `exec-out wm density`(실패해도 계속, 밀도 nil)
  /// → `exec-out uiautomator dump /dev/tty`(30초 제한, 넘으면 `.layoutTimedOut`) → 덤프 판정·해석
  /// → `exec-out 'screencap -p 2>/dev/null'`(메모리, 실패·PNG 아님·시간 초과는 `.captureFailed`). 기기에 파일을 남기지 않는다.
  /// 덤프는 실패해도 종료 코드 0 이라 `</hierarchy>` 유무로 가른다: 화면이 계속 바뀜 `.layoutNotIdle`(약 11초 뒤), 화면 꺼짐
  /// `.layoutDisplayOff`(약 2초), 다른 uiautomator 가 도는 중 `.layoutBusy`, 덤프 중 끊김 `.deviceNotBooted`, 그 밖·해석 실패·
  /// 상한(8 MiB·노드 2만·깊이 512) 초과 `.layoutUnreadable`. 자동으로 다시 시도하지 않는다.
  /// 같은 기기의 레이아웃 읽기는 앞 호출이 끝날 때까지 기다린다(한 번에 하나). 호출한 Task 가 취소되면 `.cancelled`.
  /// 좌표는 스크린샷 px, `unit` 은 `.dp`, `pixelsPerUnit` 은 밀도/160, `deviceName` 은 다시 읽은 기기의 표시 이름.
  func layoutSnapshot(on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) -> LayoutSnapshot

  /// 테스트 조건 시트가 열 때 읽는 값: `-s <serial> shell cmd uimode night` 의 `Night mode: <값>` 줄(`yes` → `.dark`, `no` → `.light`,
  /// 그 밖 → `.other`)과 `shell cmd location is-location-enabled` 의 `true`/`false`(그 밖·실패 → nil, 던지지 않는다).
  /// 사전 확인은 앱 작업과 같다. `Night mode:` 줄이 없으면(종료 코드와 관계없이) 켜는 중·끊김 출력은 `.deviceNotBooted`, 그 밖은
  /// `.unknown` (던지지 않는다: `cmd uimode night` 가 없는 Android 버전이 있을 수 있다, 미실측). 기기를 바꾸지 않는다.
  func testConditions(on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) -> AndroidTestConditions

  /// 외관을 바꾼다 (`shell cmd uimode night yes|no`). 쓰기 출력의 `Night mode:` 값이 요청과 같으면 `.applied`, 다르거나 `Error: …`
  /// 면 `.notApplied`. 출력에 `Night mode:` 줄이 없으면 한 번 다시 읽어 판정한다. 켜는 중·끊김 출력은 `.deviceNotBooted`.
  /// 실행 중 앱에 곧바로 반영되고 앱 프로세스는 그대로다 (Activity 재생성, 실측). 사전 확인은 앱 작업과 같다.
  func setNightMode(_ appearance: DeviceAppearance, on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError)
    -> AndroidConditionOutcome

  /// 기기 위치를 한 점으로 정한다 (`-s <serial> emu geo fix <경도> <위도>`: **경도 먼저**, 소수 6자리 `.` 소수점).
  /// `emu` 는 실패해도 exit 0 이라 stdout 으로 판정한다: `KO:` 줄 → `.notApplied`, `OK` 줄 → `.applied`, 둘 다 없으면 `.notApplied`.
  /// 0 이 아닌 종료 코드면 켜는 중·끊김 출력은 `.deviceNotBooted`, 그 밖 `.adbUnavailable`. 위치 서비스가 꺼져 있어도 `OK` 다(실측).
  /// 사전 확인은 앱 작업과 같다.
  func setLocation(_ coordinate: GeoCoordinate, on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError)
    -> AndroidConditionOutcome
}

/// `launchWithLogcat` 이 넘기는 알림.
public enum AndroidLogcatEvent: Hashable, Sendable {
  /// 앱을 실행하고 메인 프로세스 pid 를 얻었다 (또는 pid 전에 끝나 줄을 한 번 읽었다). 실행마다 한 번, 줄보다 먼저.
  case launched
  /// logcat 줄(`-v threadtime`), 받은 순서대로 (줄 끝 문자는 뺐다). 버퍼 머리 줄은 없다.
  case lines([String])
}

/// `launchWithLogcat` 의 끝.
public enum AndroidLogcatEnd: Hashable, Sendable {
  /// 앱 메인 프로세스가 끝났다 (종료·크래시·force-stop·다시 설치·다른 실행. 원인은 가르지 못한다).
  case appExited
  /// 앱이 끝나기 전에 adb 가 끝났다 (기기 꺼짐·adb 연결 끊김).
  case connectionLost
  /// 호출한 Task 가 취소되어 멈췄다 (앱은 남는다). `.launched` 전이면 그것을 부르지 않았다.
  case stopped
}

/// 끝난 녹화의 결과. 실패(화면이 없거나 가져오지 못함)는 `AndroidEmulatorError` 로 던진다.
public enum AndroidScreenRecordingResult: Hashable, Sendable {
  /// 멈춤 요청으로 끝나고 화면이 담긴 파일을 가져왔다.
  case saved
  /// 요청 없이 정상 종료로 끝나고(API 33 이하의 3분 제한) 화면이 담긴 파일을 가져왔다.
  case savedAtTimeLimit
  /// 녹화가 실패로 끝났거나 마무리를 확인하지 못했지만 화면이 담긴 파일을 가져왔다.
  case savedAfterFailure
  /// 화면을 담기 전에 멈췄다 (파일 없음·0바이트).
  case stoppedBeforeStart
}

/// 목록 읽기 결과.
public struct AndroidDeviceInventory: Hashable, Sendable {
  /// 읽은 순서 (화면 정렬은 Core `AndroidDeviceList`).
  public let devices: [AndroidVirtualDevice]
  /// 지금 SDK 에 설치된 이미지로 만든 선택지.
  public let creationOptions: AndroidDeviceCreationOptions
  /// false 면 SDK 를 쓸 수 없어 잠금 파일만으로 읽은 목록 (모든 기기 `.sdkUnavailable`, 선택지 비어 있음).
  public let sdkAvailable: Bool

  public init(
    devices: [AndroidVirtualDevice],
    creationOptions: AndroidDeviceCreationOptions,
    sdkAvailable: Bool = true
  ) {
    self.devices = devices
    self.creationOptions = creationOptions
    self.sdkAvailable = sdkAvailable
  }
}

/// 삭제 결과.
public enum AndroidDeleteOutcome: Hashable, Sendable {
  case deleted
  /// 목록(ini)에서는 지웠지만 기기 폴더가 예상한 위치(`.avd` 로 끝나는 실제 디렉터리)가 아니어서 남겼다.
  case folderKept(URL)
}

/// 기기 작업 실패. 화면 문구는 Feature 가 정한다.
public enum AndroidEmulatorError: Error, Hashable, Sendable {
  /// SDK 위치 문제, emulator·adb 실행 파일 없음·실행 권한 없음. 목록 읽기·삭제에서는 나오지 않는다 (잠금만으로 읽는다).
  case sdkUnavailable
  case deviceNotFound
  case deviceUnavailable(AndroidVirtualDevice.UnavailableReason)
  /// 삭제·초기화 거절: 기기가 켜져 있다(켜는 중 포함).
  case deviceRunning
  /// emulator 를 띄우지 못했다 (`launch` 의 `.launchFailed`).
  case emulatorLaunchFailed
  /// 완료 전에 끝났다. nil = 앱이 띄우지 않고 기다리기만 한 에뮬레이터라 종료 코드를 모른다.
  case emulatorExited(Int32?)
  case bootTimedOut
  /// adb 실행·서버 시작 실패, 또는 끌 기기를 adb 로 확인하지 못했다(adb 가 답하지 않거나, 이름에 답하는 기기에 `emu kill` 이 실패).
  /// 테스트 조건의 `emu geo fix` 가 켜는 중·끊김 출력 없이 0 이 아닌 종료 코드로 끝났을 때도.
  case adbUnavailable
  case shutdownTimedOut
  case invalidDeviceName(DeviceNameProblem)
  /// `_99` 까지 모두 이름이 겹친다.
  case nameUnavailable
  /// 고른 이미지·화면 모양을 지금 만들 수 없다.
  case creationOptionUnavailable
  /// `~/.android/avd` 를 읽거나 만들거나 쓰지 못했다 (권한·디스크 가득).
  case avdFolderUnavailable
  /// 지우기 도중 실패했다 (일부만 지워졌을 수 있다).
  case fileOperationFailed
  /// 초기화: 기기 폴더가 링크이거나 `.avd` 로 끝나지 않는다. 아무것도 지우지 않았다. 경로를 모르면 nil.
  case unsafeDeviceFolder(URL?)
  case cancelled
  /// 앱 작업: 기기가 켜져 있지 않다 (꺼짐·켜는 중, 또는 adb 가 offline·not found·`device is still booting`·`Can't find service`·
  /// `Too early` 로 답함). 테스트 조건의 `shell cmd uimode`·`emu geo fix` 출력도 같은 판정.
  case deviceNotBooted
  case installFailed(AndroidInstallFailure)
  /// 설치가 10분 안에 끝나지 않았다.
  case installTimedOut
  case launchFailed(AndroidLaunchFailure)
  /// 링크를 받을 앱이 없다 (`unable to resolve Intent`).
  case urlNotHandled
  /// am·pm 이 그 밖의 이유로 실패했다 (종료 코드 ≠ 0, 해석할 수 없는 출력).
  case appCommandFailed
  /// 스크린샷: 기기 화면을 읽지 못했다 (종료 코드 ≠ 0, PNG 아님, 시간 초과).
  case captureFailed
  /// 스크린샷·녹화: Mac 의 예약 파일에 쓰지 못했다 (파일 없음·링크·디스크·폴더).
  case captureFileUnwritable
  /// 녹화를 시작하지 못했다: 화면 없이 실패로 끝났다 (경로·인코더·기기 저장 공간).
  case recordingFailed
  /// 녹화가 끝났는데 가져온 파일이 0바이트이거나 없다.
  case recordingEmpty
  /// 녹화를 시작하지 못했다: 기기 화면이 꺼져 있다 (화면이 여럿인 기기에서 screenrecord 가 `UNASSIGNED_LAYER_STACK` 로 끝남, 실측).
  case recordingDisplayOff
  /// 녹화가 끝났지만 기기가 꺼지거나 adb 가 끊겨 가져오지 못했다 (기기 임시 파일은 남는다).
  case recordingLost
  /// 녹화 파일 가져오기가 시간 제한(600초) 안에 끝나지 않았다 (기기 임시 파일은 남는다).
  case recordingTransferTimedOut
  /// 레이아웃: 화면이 계속 바뀌어(애니메이션·동영상) 덤프가 idle 을 기다리다 포기했다 (`could not get idle state`).
  case layoutNotIdle
  /// 레이아웃: 기기 화면이 꺼져 있다 (`null root node returned by UiTestAutomationBridge`).
  case layoutDisplayOff
  /// 레이아웃: 같은 기기에서 다른 uiautomator(UI 테스트 도구 등)가 돌고 있어 덤프가 죽었다 (`Killed`).
  case layoutBusy
  /// 레이아웃: 덤프를 해석하지 못했다 (그 밖의 출력, `</hierarchy>` 없음, XML 오류, 상한 초과).
  case layoutUnreadable
  /// 레이아웃: 덤프가 시간 제한(30초) 안에 끝나지 않았다.
  case layoutTimedOut
}

/// adb install 실패 원인 (`Failure [<코드>: …]` 의 코드).
public enum AndroidInstallFailure: Hashable, Sendable {
  /// `INSTALL_FAILED_OLDER_SDK`: minSdk > 기기 API.
  case olderSDK
  /// `INSTALL_FAILED_NO_MATCHING_ABIS`.
  case noMatchingABIs
  /// `INSTALL_FAILED_UPDATE_INCOMPATIBLE`·`INSTALL_FAILED_SHARED_USER_INCOMPATIBLE`: 같은 패키지가 다른 서명으로 있다.
  case updateIncompatible
  /// `INSTALL_FAILED_VERSION_DOWNGRADE`.
  case versionDowngrade
  /// `INSTALL_PARSE_FAILED_NO_CERTIFICATES`: 서명 없음·내용 변조.
  case noCertificates
  /// `INSTALL_PARSE_FAILED_NOT_APK`·`INSTALL_FAILED_INVALID_APK`, adb 의 `filename doesn't end .apk`.
  case notAPK
  /// `INSTALL_FAILED_DEPRECATED_SDK_VERSION`: targetSdk 가 기기의 하한보다 낮다.
  case deprecatedSDK
  /// `INSTALL_FAILED_INSUFFICIENT_STORAGE`.
  case insufficientStorage
  /// `INSTALL_FAILED_DUPLICATE_PERMISSION`·`INSTALL_FAILED_CONFLICTING_PROVIDER`.
  case conflict
  /// `INSTALL_FAILED_MISSING_SHARED_LIBRARY`.
  case missingSharedLibrary
  /// `INSTALL_FAILED_TEST_ONLY` (`-t` 를 주므로 나오지 않아야 한다).
  case testOnly
  /// `INSTALL_FAILED_MISSING_SPLIT`: 분할 apk 의 일부.
  case missingSplit
  /// 그 밖의 `INSTALL_*` 코드(그대로), 또는 코드를 찾지 못함(nil).
  case other(String?)
}

/// 앱 실행 실패 원인.
public enum AndroidLaunchFailure: Hashable, Sendable {
  case notInstalled
  /// 설치되어 있지만 홈 화면에서 여는 화면(launcher activity)이 없다.
  case noLauncherActivity
}
