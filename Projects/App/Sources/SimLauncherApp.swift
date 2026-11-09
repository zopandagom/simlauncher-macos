import AndroidDevicesFeature
import AndroidEmulatorImpl
import AndroidPackageImpl
import AndroidSDKImpl
import AndroidSetupFeature
import AppBundleImpl
import AppLogImpl
import CommandImpl
import Core
import DevEnvironmentImpl
import DeviceLogFeature
import DownloadImpl
import Foundation
import LauncherFeature
import LayoutInspectorFeature
import PreferencesImpl
import ScreenLayoutImpl
import SettingsFeature
import SetupFeature
import SimulatorImpl
import SwiftUI
import WorkspaceImpl

/// 조립 지점. Client Impl 을 만들어 Feature Model 에 주입하는 곳은 여기뿐이다.
/// 메인 창(`MainWindow`)은 사이드바로 iOS / Android 칸을 나눈다. 화면 간 흐름도 여기서 잇는다: iOS 칸은 Setup 이 끝나면
/// (`SetupModel.isFinished`) 기기 목록, 기기 목록의 Setup 진입 버튼("개발 환경", 빈 화면의 iOS 설치 등)이면 다시 Setup.
/// Android 칸도 같다: 도구 화면에서 기기 목록으로 넘어가면(`AndroidSetupModel.isFinished`: 첫 확인이 셋 다 설치됨이거나
/// "기기 목록 열기") Android 기기 목록(`AndroidDevicesModel`),
/// 기기 목록의 "Android 도구" 버튼이면 다시 Android 도구 화면. 앱 종료 요청은 `AppDelegate` 가 받아, 기다릴 것(iOS·Android
/// 녹화·런타임 설치·Android 도구 설치)이 있으면 두 기기 목록(`LauncherModel`·`AndroidDevicesModel`)·Setup·Android 도구 화면에
/// 함께 종료를 알리고 모두 끝나기를 기다린다 (녹화 저장과 두 설치의 멈춤·취소를 함께 시작한다).
/// 기기 행·툴바의 "카탈로그에서…" 시트(`CatalogInstallModel`)가 고른 버전은 `installRequested` 로 기기 목록(`LauncherModel`)이 설치한다.
/// iOS 기기 행의 "앱 실행…"·"링크 열기…" 시트(`LauncherAppSheetsModel`)도 확정한 앱·링크를 기기 목록에 넘기고(앱 실행 시트의 켜기·
/// 다시 읽기도 기기 목록이 한다), 두 Model 의 시트끼리 서로 막는 것도 App 이 클로저로 잇는다 (Android 와 같다).
/// Android 기기 행의 "URL 에서…"·"카탈로그에서…" 시트(`AndroidDownloadInstallModel`)가 고른 주소·버전도 같은 방식으로 Android 기기
/// 목록(`AndroidDevicesModel`)이 받아 설치한다. Android 기기 행의 "앱 실행…"·"링크 열기…" 시트(`AndroidAppSheetsModel`)도 확정한
/// 앱·링크를 같은 방식으로 넘기고, 두 Model 의 시트끼리 서로 막는 것도 App 이 클로저로 잇는다 (Model 끼리 참조하지 않는다).
/// 설정 창(`Settings` 씬, ⌘,)은 메인 창의 칸·화면과 관계없이 열리고, 설정 창에서 Android SDK 위치를 바꾸면
/// `androidSDKLocationChanged` 로 Android 도구 화면이 다시 확인하고 Android 기기 목록이 (보이면) 다시 읽는다 (같은 앱의 다른 창이라
/// 앱 활성화 알림이 오지 않는다). iOS·Android 기기 행 "로그 보기" 는 로그 창(`WindowGroup(id: AppLogTarget.windowID, for: AppLogTarget.self)`,
/// 기기당 창 하나, 복원 끔)을 연다. 모든 로그 창이 App 이 소유한 `DeviceLogModel` 하나를 함께 쓰고, 창을 닫아도 받기와 앱은 계속된다.
/// 앱 로그 받기는 종료 요청 때 묻지 않고, 종료가 정해지면 `AppDelegate` 가 `stopAll()` 로 기다리지 않고 멈춘다 (iOS 앱은 꺼지고
/// Android 앱은 남는다).
/// Android 기기 행 "레이아웃 보기" 는 레이아웃 창(`WindowGroup(id: LayoutTarget.windowID, for: LayoutTarget.self)`, 기기당 창 하나,
/// 복원 끔. 같은 기기라도 로그 창과 다른 창)을 연다. 모든 레이아웃 창이 App 이 소유한 `LayoutInspectorModel` 하나를 함께 쓰고,
/// 창을 닫으면 읽기를 취소하고 스냅샷을 버린다 (스냅샷은 메모리에만 있다). 종료 요청 때 묻지 않는다.
/// Android 기기(에뮬레이터)는 녹화 밖에는 종료 요청 때 보지 않는다 (켜진 에뮬레이터는 앱이 끝나도 남는다.
/// apk 받기·설치·실행·링크 열기도 묻지 않는다. 남은 받기 폴더는 다음에 iOS 기기 목록·Android 기기 목록·Android 도구 화면 중 하나가
/// 열릴 때 지운다).
@main
struct SimLauncherApp: App {
  @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
  @State private var setupModel: SetupModel
  @State private var launcherModel: LauncherModel
  @State private var catalogInstallModel: CatalogInstallModel
  @State private var launcherAppSheetsModel: LauncherAppSheetsModel
  @State private var settingsModel: SettingsModel
  @State private var androidSetupModel: AndroidSetupModel
  @State private var androidDevicesModel: AndroidDevicesModel
  @State private var androidDownloadInstallModel: AndroidDownloadInstallModel
  @State private var androidAppSheetsModel: AndroidAppSheetsModel
  @State private var deviceLogModel: DeviceLogModel
  @State private var layoutInspectorModel: LayoutInspectorModel

  /// 명령 실행 Client 하나를 개발 환경·시뮬레이터·앱 번들 Client 가 함께 쓰고,
  /// 개발 환경 Client 하나를 Setup 과 시뮬레이터의 개발자 디렉터리가 함께 쓰며,
  /// 시뮬레이터 Client 하나를 Setup(Xcode 가 준비된 뒤 런타임 목록 읽기)과 Launcher(기기 목록·앱 실행 시트의 설치된 앱 목록),
  /// 앱 로그 Client 가 함께 쓴다.
  /// 앱 로그 Client 하나를 Launcher·Android 기기 목록(로그 받기와 함께 실행·행의 "로그 보기")과 로그 창, 종료 처리(`AppDelegate`)가
  /// 함께 쓴다.
  /// 받기 Client 는 하나만 만들어 Launcher 의 URL·카탈로그 설치, 카탈로그에서 설치 시트의 카탈로그 받기,
  /// 설정 창의 카탈로그 등록 확인, Android 기기 목록의 URL·카탈로그 설치와 그 시트의 카탈로그 받기가 함께 쓴다
  /// (지금 받는 폴더 목록을 그 안에서 함께 써, 한쪽의 남은 폴더 정리가 다른 쪽이 받는 중인 폴더를 지우지 않는다).
  /// 설정 Client 도 하나만 만들어 설정 창(카탈로그 등록·삭제, Android SDK 위치)과 카탈로그에서 설치 시트(읽기만),
  /// Android 도구 화면(라이선스 동의 기록), Android SDK Client 의 위치 provider 가 함께 쓴다
  /// (같은 프로세스의 쓰기를 Impl 안의 `Mutex` 로 묶는다). 앱 번들 Client 하나를 Launcher 와 Android SDK Client 의 호스트
  /// 아키텍처(Rosetta 로 돌아도 arm64)에 함께 쓴다. Android SDK Client 도 받기 Client 를 Launcher 와 함께 쓴다.
  /// Android 기기 Client 는 명령 실행 Client·SDK 위치 provider·호스트 아키텍처를 Android SDK Client 와 함께 쓴다. Android 기기 Client
  /// 하나를 Android 기기 목록·앱 실행 시트와 앱 로그 Client·레이아웃 Client(레이아웃 창)가 함께 쓴다 (Impl 은 이 앱이 띄운 에뮬레이터 표를 가져 하나만 만든다).
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
    let appBundle = AppBundleClientImpl(command: command)
    let home = FileManager.default.homeDirectoryForCurrentUser
    let shared = SharedClients(command: command, download: download, preferences: preferences, appBundle: appBundle)
    let androidClients = Self.makeAndroidClients(shared, home: home)
    // 앱 로그 Client 생성자는 명령을 실행하지 않는다. 받기는 설치 후 실행·행의 "앱 실행…"·창의 "다시 실행" 때만 시작한다.
    // Android 기기 Client 는 Android 기기 목록·앱 실행 시트와 같은 인스턴스다 (Impl 은 이 앱이 띄운 에뮬레이터 표를 가져 하나만 만든다).
    let appLog = AppLogClientImpl(simulator: simulator, androidEmulator: androidClients.emulator)
    // 레이아웃 창의 Client 도 같은 Android 기기 Client 를 조합한다 (생성자는 명령을 실행하지 않는다. 읽기는 창이 열릴 때와
    // "새로 고침" 때만).
    let screenLayout = ScreenLayoutClientImpl(androidEmulator: androidClients.emulator)
    self._layoutInspectorModel = State(initialValue: LayoutInspectorModel(screenLayout: screenLayout))
    let android = Self.makeAndroid(shared, clients: androidClients, appLog: appLog)
    self._androidSetupModel = State(initialValue: android.setup)
    self._androidDevicesModel = State(initialValue: android.devices)
    self._androidDownloadInstallModel = State(initialValue: android.downloadInstall)
    self._androidAppSheetsModel = State(initialValue: android.appSheets)
    let setup = SetupModel(devEnvironment: devEnvironment, simulator: simulator)
    self._setupModel = State(initialValue: setup)
    self._deviceLogModel = State(initialValue: DeviceLogModel(appLog: appLog, preferences: preferences))
    let launcherAssembly = Self.makeLauncher(
      simulator: simulator,
      appBundle: appBundle,
      download: download,
      appLog: appLog,
      setup: setup
    )
    let launcher = launcherAssembly.model
    self._launcherModel = State(initialValue: launcher)
    self._launcherAppSheetsModel = State(initialValue: launcherAssembly.sheets)
    // 카탈로그는 시트를 열 때와 새로 고칠 때만 받는다 (앱 시작 때·기기 목록을 볼 때는 받지 않는다).
    self._catalogInstallModel = State(initialValue: CatalogInstallModel(
      preferences: preferences,
      download: download,
      installRequested: { request in await launcher.catalogInstallRequested(request) }
    ))
    self._settingsModel = State(initialValue: Self.makeSettings(preferences, download, android, home))
    // 종료 요청 때 AppDelegate 가 Setup 에 설치 상태를 묻는다: 준비·내려받기 중이면 확인을 받아 멈추게 하고,
    // 설치 단계·멈추는 중이면 끝나기를 기다린다 (어댑터는 init 에서 넣은 값을 종료 요청 때 그대로 본다, 측정).
    // 두 기기 목록(iOS·Android)에는 녹화 중인지 묻는다: 어느 쪽이든 녹화 중이면 확인을 한 번 받아 모든 녹화를 멈추고 저장한 뒤
    // 종료한다.
    // Android 도구 화면에는 설치 상태를 묻는다: 받기·확인·풀기 중이면 확인을 받아 멈추게 하고, 마무리 단계면 끝나기를 기다린다.
    // 앱 로그 받기는 묻지 않고, 종료가 정해지면 모두 멈춘다 (SIGINT 를 보내고 기다리지 않는다. iOS 앱은 꺼지고 Android 앱은 남는다).
    self.appDelegate.setupModel = setup
    self.appDelegate.appLog = appLog
    self.appDelegate.launcherModel = launcher
    self.appDelegate.androidSetupModel = android.setup
    self.appDelegate.androidDevicesModel = android.devices
  }

  /// iOS 기기 목록과 앱 실행·링크 열기 시트의 Model 을 조립한다 (`init` 안에서 쓰는 값 묶음).
  private struct LauncherAssembly {
    let model: LauncherModel
    let sheets: LauncherAppSheetsModel
  }

  private static func makeLauncher(
    simulator: SimulatorClientImpl,
    appBundle: AppBundleClientImpl,
    download: DownloadClientImpl,
    appLog: AppLogClientImpl,
    setup: SetupModel
  ) -> LauncherAssembly {
    // 스크린샷·녹화 저장 폴더는 "스크린샷"·"녹화" 를 누를 때 만든다 (Workspace Client 생성자는 파일을 건드리지 않는다).
    // 앱 실행·링크 열기 시트가 떠 있으면 만들기·삭제·초기화·URL 설치 시트를 막는다. 시트 Model 은 뒤에 만들어 상자로 넘긴다.
    let launcherSheetsBox = LauncherAppSheetsBox()
    let launcher = LauncherModel(
      simulator: simulator,
      appBundle: appBundle,
      download: download,
      workspace: WorkspaceClientImpl(),
      appLog: appLog,
      setupRequested: { setup.reopened() },
      appSheetPresented: { launcherSheetsBox.model?.hasPresentedSheet ?? false }
    )
    // 앱 실행·링크 열기 시트. 열 수 있는 기기는 기기 목록에 묻고(만들기·URL 설치 시트·확인 대화상자·작업 중이면 열지 않는다),
    // 앱 실행 시트의 켜기·다시 읽기와 확정한 앱·링크의 실행은 기기 목록이 한다. 목록 읽기(`simctl listapps`)는 시트를 열 때만 한다.
    let launcherSheets = LauncherAppSheetsModel(
      simulator: simulator,
      target: { id, task in launcher.appSheetTarget(id, for: task) },
      prepareRequested: { id in await launcher.launchAppPreparationRequested(id) },
      refreshRequested: { await launcher.refreshButtonTapped() },
      launchRequested: { request in await launcher.launchAppRequested(request) },
      openURLRequested: { request in await launcher.openURLRequested(request) }
    )
    launcherSheetsBox.model = launcherSheets
    return LauncherAssembly(model: launcher, sheets: launcherSheets)
  }

  /// Android 칸의 Client 와 Model 을 조립한다 (`init` 안에서 쓰는 값 묶음).
  private struct AndroidAssembly {
    let sdk: AndroidSDKClientImpl
    let setup: AndroidSetupModel
    let devices: AndroidDevicesModel
    let downloadInstall: AndroidDownloadInstallModel
    let appSheets: AndroidAppSheetsModel
  }

  /// 설정 창의 내용은 앱 시작 때 한 번 만들어진다(측정). 생성자는 Client 를 저장만 하고, 목록 읽기는 창을 열 때,
  /// 카탈로그 받기는 "등록" 을 누를 때만 한다. SDK 위치를 바꾸면 Android 도구 화면에 알린다.
  private static func makeSettings(
    _ preferences: PreferencesClientImpl,
    _ download: DownloadClientImpl,
    _ android: AndroidAssembly,
    _ home: URL
  ) -> SettingsModel {
    SettingsModel(
      preferences: preferences,
      download: download,
      androidSDK: android.sdk,
      home: home,
      androidSDKLocationChanged: {
        Task { await android.setup.sdkLocationChanged() }
        Task { await android.devices.sdkLocationChanged() }
      }
    )
  }

  /// iOS·Android 칸이 함께 쓰는 Client (`init` 안에서 쓰는 값 묶음).
  private struct SharedClients {
    let command: CommandClientImpl
    let download: DownloadClientImpl
    let preferences: PreferencesClientImpl
    let appBundle: AppBundleClientImpl
  }

  /// Android SDK 위치 provider 와 Android 기기 Client. 앱 로그 Client 와 Android 칸이 함께 쓰므로 `makeAndroid` 앞에서 만든다.
  private struct AndroidClients {
    let sdkRoot: @Sendable () async -> AndroidSDKRootChoice
    let emulator: AndroidEmulatorClientImpl
  }

  private static func makeAndroidClients(_ shared: SharedClients, home: URL) -> AndroidClients {
    let command = shared.command
    let preferences = shared.preferences
    let appBundle = shared.appBundle
    // SDK 위치는 공개 메서드마다 설정을 다시 읽어 정한다 (기본 ~/Library/Android/sdk, 설정 창에서 고른 폴더). ANDROID_HOME 은 보지 않는다.
    // Client 생성자는 파일·네트워크·명령을 건드리지 않는다. 확인은 Android 칸이 보일 때 한다.
    let sdkRoot: @Sendable () async -> AndroidSDKRootChoice = {
      AndroidSDKRootChoice.resolve(preferences.androidSDKPath().value, home: home)
    }
    // AVD 폴더는 ~/.android/avd (Android Studio 와 함께 쓴다). 생성자는 파일·명령을 건드리지 않고,
    // 기기 목록은 Android 칸의 기기 목록 화면이 보일 때 읽는다.
    let emulator = AndroidEmulatorClientImpl(
      command: command,
      sdkRoot: sdkRoot,
      home: home,
      host: AndroidHostArchitecture(appBundle.hostArchitecture)
    )
    return AndroidClients(sdkRoot: sdkRoot, emulator: emulator)
  }

  private static func makeAndroid(
    _ shared: SharedClients,
    clients: AndroidClients,
    appLog: AppLogClientImpl
  ) -> AndroidAssembly {
    let command = shared.command
    let download = shared.download
    let preferences = shared.preferences
    let appBundle = shared.appBundle
    let sdk = AndroidSDKClientImpl(
      download: download,
      command: command,
      hostArchitecture: appBundle.hostArchitecture,
      sdkRoot: clients.sdkRoot
    )
    let emulator = clients.emulator
    let setup = AndroidSetupModel(
      androidSDK: sdk,
      preferences: preferences,
      workspace: WorkspaceClientImpl()
    )
    // apk 검사(zipinfo·unzip)는 같은 Command Client 로 실행한다. 생성자는 파일·명령을 건드리지 않는다.
    // 받기는 Launcher 와 같은 Download 인스턴스다 (화면을 열 때 남은 받기 폴더를 지운다).
    // 앱 실행·링크 열기 시트가 떠 있으면 만들기·삭제·초기화를 막는다. 시트 Model 은 뒤에 만들어 상자로 넘긴다.
    // 스크린샷·녹화 저장 폴더는 "스크린샷"·"녹화" 를 누를 때 만든다 (Workspace Client 생성자는 파일을 건드리지 않는다).
    let appSheetsBox = AndroidAppSheetsBox()
    let devices = AndroidDevicesModel(
      emulator: emulator,
      package: AndroidPackageClientImpl(command: command),
      download: download,
      appLog: appLog,
      workspace: WorkspaceClientImpl(),
      setupRequested: { setup.reopened() },
      appSheetPresented: { appSheetsBox.model?.hasPresentedSheet ?? false }
    )
    // 앱 실행·링크 열기 시트와 행 "로그 보기" 를 누를 수 있는 기기(앱 로그 세션 구독은 기기 목록 화면이 처음 보일 때 시작한다).
    // 열 수 있는 기기는 기기 목록에 묻고(만들기 시트·확인 대화상자·작업 중이면 열지 않는다), 확정한 앱·링크는 기기 목록이
    // 실행한다 (실행은 앱 로그 받기와 함께).
    let appSheets = AndroidAppSheetsModel(
      emulator: emulator,
      appLog: appLog,
      target: { id, task in devices.appSheetTarget(id, for: task) },
      launchRequested: { request in await devices.launchAppRequested(request) },
      openURLRequested: { request in await devices.openURLRequested(request) }
    )
    appSheetsBox.model = appSheets
    // URL·카탈로그 시트. 카탈로그는 시트를 열 때와 새로 고칠 때만 받고, 고른 주소·버전은 기기 목록이 받아 설치한다.
    let downloadInstall = AndroidDownloadInstallModel(
      preferences: preferences,
      download: download,
      installRequested: { request in await devices.downloadInstallRequested(request) }
    )
    return AndroidAssembly(
      sdk: sdk,
      setup: setup,
      devices: devices,
      downloadInstall: downloadInstall,
      appSheets: appSheets
    )
  }

  var body: some Scene {
    WindowGroup {
      MainWindow(
        setupModel: self.setupModel,
        launcherModel: self.launcherModel,
        catalogInstallModel: self.catalogInstallModel,
        launcherAppSheetsModel: self.launcherAppSheetsModel,
        androidSetupModel: self.androidSetupModel,
        androidDevicesModel: self.androidDevicesModel,
        androidDownloadInstallModel: self.androidDownloadInstallModel,
        androidAppSheetsModel: self.androidAppSheetsModel
      )
    }
    // 기기 행 "로그 보기" 가 여는 로그 창. 같은 기기(값)면 창 하나이고, 앱 시작 때 열리지 않는다(측정). 받은 로그는 메모리에만
    // 있어 앱을 다시 켜면 없으므로 창을 되살리지 않는다. 창을 닫아도 받기는 계속된다 (DeviceLogView 의 onDisappear 는 구독만 끊는다).
    WindowGroup(id: AppLogTarget.windowID, for: AppLogTarget.self) { $target in
      if let target {
        DeviceLogView(model: self.deviceLogModel, target: target)
      }
    }
    .defaultSize(width: 900, height: 600)
    .restorationBehavior(.disabled)
    // Android 기기 행 "레이아웃 보기" 가 여는 레이아웃 창. 같은 기기(값)면 창 하나이고, 스냅샷은 메모리에만 있어 되살리지 않는다.
    // 창을 닫으면 읽기를 취소하고 스냅샷을 버린다 (LayoutInspectorView 의 onDisappear).
    WindowGroup(id: LayoutTarget.windowID, for: LayoutTarget.self) { $target in
      if let target {
        LayoutInspectorView(model: self.layoutInspectorModel, target: target)
      }
    }
    .defaultSize(width: 1100, height: 760)
    .restorationBehavior(.disabled)
    // 창을 닫으면 진행 중인 등록 확인을 취소한다 (SettingsView 의 onDisappear).
    Settings {
      SettingsView(model: self.settingsModel)
    }
  }
}

/// iOS 기기 목록 Model 을 먼저 만들어야 하므로(시트 Model 의 `target` 이 그것을 쓴다), 기기 목록의 `appSheetPresented` 가 뒤에
/// 만든 시트 Model 을 읽게 넘기는 상자. `AndroidAppSheetsBox` 와 같다.
@MainActor
private final class LauncherAppSheetsBox {
  weak var model: LauncherAppSheetsModel?
}

/// 기기 목록 Model 을 먼저 만들어야 하므로(시트 Model 의 `target` 이 그것을 쓴다), 기기 목록의 `appSheetPresented` 가 뒤에
/// 만든 시트 Model 을 읽게 넘기는 상자. App 안에서만 쓴다. 시트 Model 은 App 이 `@State` 로 소유하므로 약하게 잡는다.
@MainActor
private final class AndroidAppSheetsBox {
  weak var model: AndroidAppSheetsModel?
}
