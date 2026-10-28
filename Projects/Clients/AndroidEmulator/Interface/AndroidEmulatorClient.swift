import Core
import Foundation

/// Android 기기(AVD) 목록·상태와 켜기·끄기·만들기·삭제·초기화.
/// AVD 폴더는 `$HOME/.android/avd` (Android Studio 와 함께 쓴다. ANDROID_AVD_HOME 은 보지 않는다).
/// SDK 위치는 App 이 주입한 provider 를 공개 메서드 한 번에 한 번 부른다. 명령은 CommandClient 로
/// `<SDK>/emulator/emulator` 와 `<SDK>/platform-tools/adb` 만 실행한다. 네트워크 API 를 쓰지 않는다
/// (에뮬레이터 자체의 Google 접속은 ARCHITECTURE §4 네트워크 행).
public protocol AndroidEmulatorClient: Sendable {
  /// AVD 목록과 만들기 선택지. 파일을 읽고, 실행 중인 AVD 가 있을 때만 adb 를 부른다 (없으면 명령 없음).
  /// 메인 밖에서 돈다. SDK 위치가 쓸 수 없거나 emulator·platform-tools 실행 파일이 없으면 `.sdkUnavailable`.
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
  /// 실행 직전에 다시 읽은 선택지에 이미지·프로필이 없으면 `.creationOptionUnavailable`.
  /// AVD 이름은 `AndroidAVDName.make` (다시 읽은 목록 기준). 폴더·ini 를 덮어쓰지 않는다(독점 생성).
  func create(
    displayName: String,
    image: AndroidSystemImageRef,
    profile: AndroidDeviceProfile.ID
  ) async throws(AndroidEmulatorError) -> AndroidVirtualDevice.ID

  /// 꺼진 AVD 를 지운다. 목록 읽기와 같이 SDK 를 쓸 수 없으면 `.sdkUnavailable` (SDK 없이 지우기는 후속).
  /// 실행 직전에 다시 읽은 폴더 목록에서 `<id>.ini` 항목을 찾아(이름으로 경로를 만들지 않는다)
  /// 없으면 `.deviceNotFound`, 잠금·adb 로 다시 확인해 실행 중이면 `.deviceRunning`.
  /// `path` 가 `.avd` 로 끝나는 실제 디렉터리(링크 아님)일 때만 폴더를 지우고, 아니면 ini 만 지운 뒤 `.folderKept(path)` 를 돌려준다.
  func delete(_ id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) -> AndroidDeleteOutcome

  /// 꺼진 AVD 의 사용자 데이터·스냅샷을 지운다 (`AndroidAVDReset`, 링크는 따라가지 않고 링크만 지운다). 켜지 않는다.
  /// 사전 확인(SDK 확인 포함)은 `delete` 와 같다. 쓸 수 없는 기기는 `.deviceUnavailable`. 기기 폴더가 링크이거나 `.avd` 로 끝나지 않으면
  /// `.unsafeDeviceFolder` (아무것도 지우지 않는다).
  func erase(_ id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError)
}

/// 목록 읽기 결과.
public struct AndroidDeviceInventory: Hashable, Sendable {
  /// 읽은 순서 (화면 정렬은 Core `AndroidDeviceList`).
  public let devices: [AndroidVirtualDevice]
  /// 지금 SDK 에 설치된 이미지로 만든 선택지.
  public let creationOptions: AndroidDeviceCreationOptions

  public init(devices: [AndroidVirtualDevice], creationOptions: AndroidDeviceCreationOptions) {
    self.devices = devices
    self.creationOptions = creationOptions
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
  /// SDK 위치 문제, emulator·adb 실행 파일 없음·실행 권한 없음.
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
}
