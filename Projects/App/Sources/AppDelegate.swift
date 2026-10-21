import AppKit
import SetupFeature

/// 앱 종료 요청(⌘Q·메뉴)을 받는다. 런타임 설치 중이 아니면 바로 끝낸다.
/// 준비·내려받기 중이면 확인 대화상자를 띄우고, "종료"를 고르면 Setup 이 설치를 멈추게 한 뒤 끝나기를 기다렸다가 다시 종료한다.
/// 설치 단계이거나 이미 멈추는 중이면 묻지 않고, 멈추지 않은 채 끝나기를 기다린 뒤 다시 종료한다.
/// 앱이 끝나도 설치 도구(xcodebuild)가 남아 앱이 모르는 설치가 이어지지 않게 하기 위해서다.
/// 기다리는 동안은 `.terminateCancel` 을 돌려주고, 끝나면 `NSApp.terminate` 를 다시 부른다.
/// `.terminateLater` 를 쓰지 않는다: 기다리는 동안 다시 종료를 요청하면 AppKit 이 묻지 않고 바로 끝낸다(측정).
/// 신호는 보내지 않는다: 설치를 멈추는 일은 Setup Model 의 Task 취소로 하고, 프로세스 신호는 Command Client Impl 이 보낸다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// App 이 `init` 에서 넣는다. 없으면 바로 종료한다.
  var setupModel: SetupModel?
  /// 설치가 끝나기를 기다리는 중. 그동안 온 종료 요청은 거절한다 (기다림이 끝나면 앱이 스스로 종료한다).
  private var isWaitingForSetup = false

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let setup = self.setupModel, !self.isWaitingForSetup else {
      return self.isWaitingForSetup ? .terminateCancel : .terminateNow
    }
    switch setup.terminationAction {
    case .terminateNow:
      return .terminateNow
    case .confirmThenCancel:
      guard SetupTerminationPrompt.confirmQuit() else { return .terminateCancel }
    case .waitForInstall:
      break
    }
    self.isWaitingForSetup = true
    Task {
      await setup.appTerminationRequested()
      self.isWaitingForSetup = false
      NSApp.terminate(nil)
    }
    return .terminateCancel
  }
}
