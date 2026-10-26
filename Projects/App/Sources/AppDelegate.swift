import AppKit
import LauncherFeature
import SetupFeature

/// 앱 종료 요청(⌘Q·메뉴·로그아웃)을 받는다. 런타임 설치 중도 녹화 중도 아니면 바로 끝낸다.
/// 런타임 설치가 준비·내려받기 중이면 먼저 그 확인 대화상자를 띄우고, 그다음 녹화 중(저장 중 포함)이면
/// "녹화를 멈추고 저장한 뒤 종료할까요?" 를 묻는다 (둘이 겹치면 차례로 두 번 묻고, 어느 쪽이든 "취소"면 아무것도 멈추지 않는다).
/// 기다릴 것이 있으면 먼저 Launcher 가 모든 녹화를 멈추고 저장(Finder 보이기까지)하게 한 뒤, Setup 이 설치를 멈추게 하고
/// (설치 단계·멈추는 중이면 멈추지 않은 채) 끝나기를 기다렸다가 다시 종료한다. 녹화가 먼저인 것은 멈춤이 짧아
/// (마무리 측정: 짧은 녹화 0.1초 안팎, 15분 녹화 1.54초. 파일 크기에 비례) 설치 대기에 묻히지 않고, 설치를 기다리는 동안 녹화가 계속 커지지 않게 하기 위해서다.
/// 앱이 끝나도 설치 도구(xcodebuild)나 녹화(simctl)가 남아 앱이 모르는 설치·녹화가 이어지지 않게 하기 위해서다.
/// 기다리는 동안은 `.terminateCancel` 을 돌려주고, 끝나면 `NSApp.terminate` 를 다시 부른다.
/// `.terminateLater` 를 쓰지 않는다: 기다리는 동안 다시 종료를 요청하면 AppKit 이 묻지 않고 바로 끝낸다(측정).
/// 그래서 로그아웃·재시동·시스템 종료 중에 기다릴 것이 있으면 `.terminateCancel` 이 로그아웃 자체를 취소한다: 설치를 멈추거나
/// 녹화를 저장하고 앱만 끝나며, 사용자가 다시 로그아웃해야 한다.
/// 신호는 보내지 않는다: 설치·녹화를 멈추는 일은 각 Model 의 Task 취소로 하고, 프로세스 신호는 Command Client Impl 이 보낸다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// App 이 `init` 에서 넣는다. 없으면 설치를 보지 않는다.
  var setupModel: SetupModel?
  /// App 이 `init` 에서 넣는다. 없으면 녹화를 보지 않는다.
  var launcherModel: LauncherModel?
  /// 녹화 저장·설치가 끝나기를 기다리는 중. 그동안 온 종료 요청은 거절한다 (기다림이 끝나면 앱이 스스로 종료한다).
  private var isWaitingToTerminate = false

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !self.isWaitingToTerminate else { return .terminateCancel }
    let setupAction = self.setupModel?.terminationAction ?? .terminateNow
    if setupAction == .confirmThenCancel {
      guard SetupTerminationPrompt.confirmQuit() else { return .terminateCancel }
    }
    let launcher = self.launcherModel
    let isRecording = launcher?.isRecording ?? false
    if isRecording {
      guard RecordingTerminationPrompt.confirmQuit() else { return .terminateCancel }
    }
    guard isRecording || setupAction != .terminateNow else { return .terminateNow }
    self.isWaitingToTerminate = true
    let setup = setupAction == .terminateNow ? nil : self.setupModel
    Task {
      await launcher?.appTerminationRequested()
      await setup?.appTerminationRequested()
      self.isWaitingToTerminate = false
      NSApp.terminate(nil)
    }
    return .terminateCancel
  }
}
