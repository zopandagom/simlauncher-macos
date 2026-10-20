import AppBundleImpl
import CommandImpl
import DevEnvironmentImpl
import LauncherFeature
import SimulatorImpl
import SwiftUI

/// 조립 지점. Client Impl 을 만들어 Feature Model 에 주입하는 곳은 여기뿐이다.
@main
struct SimLauncherApp: App {
  @State private var launcherModel = Self.makeLauncherModel()

  var body: some Scene {
    WindowGroup {
      LauncherView(model: self.launcherModel)
    }
  }

  /// 명령 실행 Client 하나를 개발 환경·시뮬레이터·앱 번들 Client 가 함께 쓴다.
  private static func makeLauncherModel() -> LauncherModel {
    let command = CommandClientImpl()
    let devEnvironment = DevEnvironmentClientImpl(command: command)
    // 개발자 디렉터리는 DevEnvironment 가 고른 Xcode (호출마다 다시 고른다). 없으면 Simulator 는 명령을 실행하지 않는다.
    return LauncherModel(
      simulator: SimulatorClientImpl(
        developerDirectory: { await devEnvironment.selectedXcode()?.developerDirectory },
        command: command
      ),
      appBundle: AppBundleClientImpl(command: command)
    )
  }
}
