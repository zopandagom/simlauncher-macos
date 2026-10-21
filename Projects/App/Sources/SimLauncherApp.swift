import AppBundleImpl
import CommandImpl
import DevEnvironmentImpl
import LauncherFeature
import SetupFeature
import SimulatorImpl
import SwiftUI

/// 조립 지점. Client Impl 을 만들어 Feature Model 에 주입하는 곳은 여기뿐이다.
/// 화면 간 흐름도 여기서 잇는다: Setup 이 끝나면(`SetupModel.isFinished`) 기기 목록, 기기 목록의 Setup 진입 버튼
/// ("개발 환경", 빈 화면의 iOS 설치 등)이면 다시 Setup. 앱 종료 요청은 `AppDelegate` 가 받아 런타임 설치 중이면 Setup 에 맡긴다.
@main
struct SimLauncherApp: App {
  @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
  @State private var setupModel: SetupModel
  @State private var launcherModel: LauncherModel

  /// 명령 실행 Client 하나를 개발 환경·시뮬레이터·앱 번들 Client 가 함께 쓰고,
  /// 개발 환경 Client 하나를 Setup 과 시뮬레이터의 개발자 디렉터리가 함께 쓰며,
  /// 시뮬레이터 Client 하나를 Setup(Xcode 가 준비된 뒤 런타임 목록 읽기)과 Launcher 가 함께 쓴다.
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
    let setup = SetupModel(devEnvironment: devEnvironment, simulator: simulator)
    self._setupModel = State(initialValue: setup)
    self._launcherModel = State(initialValue: LauncherModel(
      simulator: simulator,
      appBundle: AppBundleClientImpl(command: command),
      setupRequested: { setup.reopened() }
    ))
    // 종료 요청 때 AppDelegate 가 Setup 에 설치 상태를 묻는다: 준비·내려받기 중이면 확인을 받아 멈추게 하고,
    // 설치 단계·멈추는 중이면 끝나기를 기다린다 (어댑터는 init 에서 넣은 값을 종료 요청 때 그대로 본다, 측정).
    self.appDelegate.setupModel = setup
  }

  var body: some Scene {
    WindowGroup {
      // 기기 목록 화면은 Setup 이 끝나야 만들어진다 (그 전에는 목록 읽기·정리가 돌지 않는다).
      // 돌아올 때마다 새로 만들어져 onAppear 가 목록을 다시 읽는다.
      if self.setupModel.isFinished {
        LauncherView(model: self.launcherModel)
      } else {
        SetupView(model: self.setupModel)
      }
    }
  }
}
