import AppBundleImpl
import CommandImpl
import DevEnvironmentImpl
import DownloadImpl
import LauncherFeature
import PreferencesImpl
import SettingsFeature
import SetupFeature
import SimulatorImpl
import SwiftUI
import WorkspaceImpl

/// 조립 지점. Client Impl 을 만들어 Feature Model 에 주입하는 곳은 여기뿐이다.
/// 화면 간 흐름도 여기서 잇는다: Setup 이 끝나면(`SetupModel.isFinished`) 기기 목록, 기기 목록의 Setup 진입 버튼
/// ("개발 환경", 빈 화면의 iOS 설치 등)이면 다시 Setup. 앱 종료 요청은 `AppDelegate` 가 받아 녹화 중이면 기기 목록(`LauncherModel`)에
/// 녹화를 멈추고 저장하게 하고, 런타임 설치 중이면 Setup 에 맡긴다.
/// 기기 행의 "카탈로그에서…" 시트(`CatalogInstallModel`)가 고른 버전은 `installRequested` 로 기기 목록(`LauncherModel`)이 설치한다.
/// 설정 창(`Settings` 씬, ⌘,)은 메인 창의 화면(Setup·기기 목록)과 관계없이 열린다.
@main
struct SimLauncherApp: App {
  @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
  @State private var setupModel: SetupModel
  @State private var launcherModel: LauncherModel
  @State private var catalogInstallModel: CatalogInstallModel
  @State private var settingsModel: SettingsModel

  /// 명령 실행 Client 하나를 개발 환경·시뮬레이터·앱 번들 Client 가 함께 쓰고,
  /// 개발 환경 Client 하나를 Setup 과 시뮬레이터의 개발자 디렉터리가 함께 쓰며,
  /// 시뮬레이터 Client 하나를 Setup(Xcode 가 준비된 뒤 런타임 목록 읽기)과 Launcher 가 함께 쓴다.
  /// 받기 Client 는 하나만 만들어 Launcher 의 URL·카탈로그 설치, 카탈로그에서 설치 시트의 카탈로그 받기,
  /// 설정 창의 카탈로그 등록 확인이 함께 쓴다 (지금 받는 폴더 목록을 그 안에서 함께 쓴다).
  /// 설정 Client 도 하나만 만들어 설정 창(등록·삭제)과 카탈로그에서 설치 시트(읽기만)가 함께 쓴다
  /// (같은 프로세스의 쓰기를 Impl 안의 `Mutex` 로 묶는다).
  init() {
    let command = CommandClientImpl()
    let devEnvironment = DevEnvironmentClientImpl(command: command)
    // 개발자 디렉터리는 DevEnvironment 가 고른 Xcode (호출마다 다시 고른다). 없으면 Simulator 는 명령을 실행하지 않는다.
    // Client 생성자는 명령을 실행하지 않는다. Setup 은 Xcode 가 준비됐다고 판정한 뒤에만 런타임 목록을 읽고,
    // 기기 목록 화면이 보이기 전에는 기기 목록을 읽는 simctl 이 돌지 않는다.
    let simulator = SimulatorClientImpl(
      developerDirectory: { await devEnvironment.selectedXcode()?.developerDirectory },
      command: command
    )
    let download = DownloadClientImpl()
    let preferences = PreferencesClientImpl()
    let setup = SetupModel(devEnvironment: devEnvironment, simulator: simulator)
    self._setupModel = State(initialValue: setup)
    // 스크린샷·녹화 저장 폴더는 "스크린샷"·"녹화" 를 누를 때 만든다 (Workspace Client 생성자는 파일을 건드리지 않는다).
    let launcher = LauncherModel(
      simulator: simulator,
      appBundle: AppBundleClientImpl(command: command),
      download: download,
      workspace: WorkspaceClientImpl(),
      setupRequested: { setup.reopened() }
    )
    self._launcherModel = State(initialValue: launcher)
    // 카탈로그는 시트를 열 때와 새로 고칠 때만 받는다 (앱 시작 때·기기 목록을 볼 때는 받지 않는다).
    self._catalogInstallModel = State(initialValue: CatalogInstallModel(
      preferences: preferences,
      download: download,
      installRequested: { request in await launcher.catalogInstallRequested(request) }
    ))
    // 설정 창의 내용은 앱 시작 때 한 번 만들어진다(측정). 생성자는 Client 를 저장만 하고, 목록 읽기는 창을 열 때,
    // 카탈로그 받기는 "등록" 을 누를 때만 한다.
    self._settingsModel = State(initialValue: SettingsModel(preferences: preferences, download: download))
    // 종료 요청 때 AppDelegate 가 Setup 에 설치 상태를 묻는다: 준비·내려받기 중이면 확인을 받아 멈추게 하고,
    // 설치 단계·멈추는 중이면 끝나기를 기다린다 (어댑터는 init 에서 넣은 값을 종료 요청 때 그대로 본다, 측정).
    // 기기 목록에는 녹화 중인지 묻는다: 녹화 중이면 확인을 받아 모든 녹화를 멈추고 저장한 뒤 종료한다.
    self.appDelegate.setupModel = setup
    self.appDelegate.launcherModel = launcher
  }

  var body: some Scene {
    WindowGroup {
      // 기기 목록 화면은 Setup 이 끝나야 만들어진다 (그 전에는 목록 읽기·정리가 돌지 않는다).
      // 돌아올 때마다 새로 만들어져 onAppear 가 목록을 다시 읽는다.
      if self.setupModel.isFinished {
        LauncherView(model: self.launcherModel, catalogModel: self.catalogInstallModel)
      } else {
        SetupView(model: self.setupModel)
      }
    }
    // 창을 닫으면 진행 중인 등록 확인을 취소한다 (SettingsView 의 onDisappear).
    Settings {
      SettingsView(model: self.settingsModel)
    }
  }
}
