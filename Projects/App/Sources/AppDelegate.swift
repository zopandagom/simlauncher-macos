import AndroidSetupFeature
import AppKit
import LauncherFeature
import SetupFeature

/// 앱 종료 요청(⌘Q·메뉴·로그아웃)을 받는다. 런타임 설치 중도 Android 도구 설치 중도 녹화 중도 아니면 바로 끝낸다.
/// 묻는 순서: 런타임 설치가 준비·내려받기 중이면 먼저 그 확인 대화상자, 그다음 Android 도구 설치가 받기·확인·풀기 중이면
/// "Android 도구 설치를 멈추고 종료할까요?", 그다음 녹화 중(저장 중 포함)이면 "녹화를 멈추고 저장한 뒤 종료할까요?" 를 묻는다
/// (여럿이 겹치면 차례로 묻고, 어느 쪽이든 "취소"면 아무것도 멈추지 않는다). 설치 단계·마무리 단계·멈추는 중이면 묻지 않는다.
/// 기다리는 방식: 묻기를 모두 통과하면 세 화면에 함께 종료를 알린다. Launcher 는 모든 녹화를 멈추고 저장(Finder 보이기까지)하고,
/// Setup 은 설치를 멈추고(설치 단계·멈추는 중이면 멈추지 않은 채) 끝나기를 기다리며, Android 도구 화면은 단계와 관계없이 설치를 취소하고
/// 끝나기를 기다린다(마무리 단계면 그 도구의 마무리만 끝내고 남은 도구는 받지 않는다). 셋 모두 첫 대기 전까지 이 호출 안에서 돌아
/// 멈춤·취소를 곧바로 시작하므로, 한쪽 대기(예: 런타임 "설치 단계" 수 분)가 다른 쪽 멈춤을 늦추지 않고 녹화가 설치를 기다리는 동안
/// 계속 커지지 않는다. 셋은 공유 자원이 없어 겹쳐도 된다. 모두 끝나면 다시 종료한다.
/// Setup·Android 는 설치 중이 아니어도 종료를 알려, 기다리는 동안 새 설치를 시작하지 않게 한다.
/// 앱이 끝나도 설치 도구(xcodebuild·unzip)나 녹화(simctl)가 남아 앱이 모르는 설치·녹화가 이어지지 않게 하기 위해서다.
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
  /// App 이 `init` 에서 넣는다. 없으면 Android 도구 설치를 보지 않는다.
  var androidSetupModel: AndroidSetupModel?
  /// 녹화 저장·설치가 끝나기를 기다리는 중. 그동안 온 종료 요청은 거절한다 (기다림이 끝나면 앱이 스스로 종료한다).
  private var isWaitingToTerminate = false

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !self.isWaitingToTerminate else { return .terminateCancel }
    let setupAction = self.setupModel?.terminationAction ?? .terminateNow
    if setupAction == .confirmThenCancel {
      guard SetupTerminationPrompt.confirmQuit() else { return .terminateCancel }
    }
    // 앞 대화상자를 띄운 동안 단계가 바뀌었을 수 있어 묻기 직전에 읽는다.
    let androidAction = self.androidSetupModel?.terminationAction ?? .terminateNow
    if androidAction == .confirmThenCancel {
      guard AndroidSetupTerminationPrompt.confirmQuit() else { return .terminateCancel }
    }
    let launcher = self.launcherModel
    let isRecording = launcher?.isRecording ?? false
    if isRecording {
      guard RecordingTerminationPrompt.confirmQuit() else { return .terminateCancel }
    }
    guard isRecording || setupAction != .terminateNow || androidAction != .terminateNow else { return .terminateNow }
    self.waitThenTerminate(launcher: launcher)
    return .terminateCancel
  }

  /// 녹화 저장·런타임 설치·Android 도구 설치의 종료 처리를 함께 시작하고, 모두 끝나기를 기다린 뒤 다시 종료한다.
  /// 기다릴 것이 없는 쪽은 종료 표시만 세우고 바로 끝난다.
  private func waitThenTerminate(launcher: LauncherModel?) {
    self.isWaitingToTerminate = true
    let setup = self.setupModel
    let androidSetup = self.androidSetupModel
    // 셋 모두 이 호출 안에서 첫 await 까지 동기로 돌아 녹화 멈춤·설치 취소·종료 표시를 함께 시작한다.
    // 하나를 기다리느라 다른 쪽 멈춤이 늦어지지 않게 하고(서로 공유 자원이 없다), 끝나기만 마지막에 모두 기다린다.
    let recording = Task.immediate { await launcher?.appTerminationRequested() }
    let runtime = Task.immediate { await setup?.appTerminationRequested() }
    let android = Task.immediate { await androidSetup?.appTerminationRequested() }
    Task {
      await recording.value
      await runtime.value
      await android.value
      self.isWaitingToTerminate = false
      NSApp.terminate(nil)
    }
  }
}
