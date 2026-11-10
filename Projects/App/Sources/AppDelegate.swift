import AndroidDevicesFeature
import AndroidSetupFeature
import AppKit
import AppLogInterface
import LauncherFeature
import ScreenLayoutImpl
import SetupFeature

/// 앱 종료 요청(⌘Q·메뉴·로그아웃)을 받는다. 런타임 설치 중도 Android 도구 설치 중도 녹화 중도 아니고 iOS 레이아웃 러너도 없으면 바로 끝낸다.
/// 묻는 순서: 런타임 설치가 준비·내려받기 중이면 먼저 그 확인 대화상자, 그다음 Android 도구 설치가 받기·확인·풀기 중이면
/// "Android 도구 설치를 멈추고 종료할까요?", 그다음 기기 목록(iOS·Android) 어느 쪽이든 녹화 중(저장 중 포함)이면
/// "녹화를 멈추고 저장한 뒤 종료할까요?" 를 한 번 묻는다
/// (여럿이 겹치면 차례로 묻고, 어느 쪽이든 "취소"면 아무것도 멈추지 않는다). 설치 단계·마무리 단계·멈추는 중이면 묻지 않는다.
/// 기다리는 방식: 묻기를 모두 통과하면 네 화면에 함께 종료를 알린다. 두 기기 목록(Launcher·Android 기기)은 모든 녹화를 멈추고
/// 저장(Android 는 기기에서 가져오기, Finder 보이기까지)하고,
/// Setup 은 설치를 멈추고(설치 단계·멈추는 중이면 멈추지 않은 채) 끝나기를 기다리며, Android 도구 화면은 단계와 관계없이 설치를 취소하고
/// 끝나기를 기다린다(마무리 단계면 그 도구의 마무리만 끝내고 남은 도구는 받지 않는다). 넷 모두 첫 대기 전까지 이 호출 안에서 돌아
/// 멈춤·취소를 곧바로 시작하므로, 한쪽 대기(예: 런타임 "설치 단계" 수 분)가 다른 쪽 멈춤을 늦추지 않고 녹화가 설치를 기다리는 동안
/// 계속 커지지 않는다. 넷은 공유 자원이 없어 겹쳐도 된다. 모두 끝나면 다시 종료한다.
/// Setup·Android 는 설치 중이 아니어도 종료를 알려, 기다리는 동안 새 설치를 시작하지 않게 한다.
/// 앱이 끝나도 설치 도구(xcodebuild·unzip)나 녹화(simctl·adb)가 남아 앱이 모르는 설치·녹화가 이어지지 않게 하기 위해서다.
/// 기다리는 동안은 `.terminateCancel` 을 돌려주고, 끝나면 `NSApp.terminate` 를 다시 부른다.
/// 녹화·설치를 기다릴 때는 `.terminateLater` 를 쓰지 않는다: 기다리는 동안 다시 종료를 요청하면 AppKit 이 묻지 않고 바로 끝낸다(측정).
/// 그래서 로그아웃·재시동·시스템 종료 중에 기다릴 것이 있으면 `.terminateCancel` 이 로그아웃 자체를 취소한다: 설치를 멈추거나
/// 녹화를 저장하고 앱만 끝나며, 사용자가 다시 로그아웃해야 한다.
/// 레이아웃 러너: iOS 레이아웃 보기가 기기에 띄운 XCUITest 러너(xcodebuild)는 묻지 않고 멈춘다(`stopAllIOSRunners`, 5초 상한:
/// 러너에 끝내기 요청 → SIGTERM → 기기에서 러너 앱 지우기). 기다릴 것이 러너 정리뿐이면 예외로 `.terminateLater` 를 돌려주고
/// 끝나면 `NSApp.reply(toApplicationShouldTerminate: true)` 로 답한다 (사용자가 모르는 조용한 정리라 로그아웃을 취소하지 않으려고).
/// 그동안 다시 종료를 요청해 AppKit 이 곧바로 끝내도 xcodebuild 에는 이미 끝내기 요청·SIGTERM 이 갔거나 러너의 10분 유휴 제한으로
/// 끝나고, 기기에 남은 러너 앱은 다음에 기기 목록이 그 기기를 켜진 것으로 읽을 때 지워진다. 녹화·설치를 기다릴 때는 러너 정리도
/// 위 기다림에 함께 시작하고, 기다린 뒤 다시 종료할 때는 러너 정리를 다시 기다리지 않는다(이미 5초 상한을 썼다).
/// 신호는 보내지 않는다: 설치·녹화를 멈추는 일은 각 Model 의 Task 취소로 하고, 프로세스 신호는 Command Client Impl 이 보낸다.
/// 앱 로그 받기는 묻지도 기다리지도 않는다: 종료가 정해지면(`applicationWillTerminate`. 바로 끝낼 때와 위 기다림 뒤 다시 종료할 때
/// 모두 지난다) `AppLogClient.stopAll()` 이 모든 받기 작업을 취소하고, 그 취소가 받던 simctl·adb 마다 그 자리에서 SIGINT 를 보낸다.
/// iOS 는 Simulator 안의 그 앱도 꺼지고 (SimLauncher 종료 때 앱이 같이 꺼지는 것은 수용한 동작이다), Android 는 adb 와 기기 안
/// logcat 만 끝나고 에뮬레이터 안의 앱은 남는다(측정). 비정상 종료면 이 경로를 거치지 않지만 iOS 는 받는 쪽 파이프가 닫혀 simctl 이
/// 끝나고 앱도 꺼진다(측정). Android 의 기기 안 logcat 이 그때 끝나는지는 확인하지 못했다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// App 이 `init` 에서 넣는다. 없으면 설치를 보지 않는다.
  var setupModel: SetupModel?
  /// App 이 `init` 에서 넣는다. 없으면 녹화를 보지 않는다.
  var launcherModel: LauncherModel?
  /// App 이 `init` 에서 넣는다. 없으면 Android 도구 설치를 보지 않는다.
  var androidSetupModel: AndroidSetupModel?
  /// App 이 `init` 에서 넣는다. 없으면 Android 녹화를 보지 않는다.
  var androidDevicesModel: AndroidDevicesModel?
  /// App 이 `init` 에서 넣는다. 없으면 앱 로그 받기를 멈추지 않는다.
  var appLog: (any AppLogClient)?
  /// App 이 `init` 에서 넣는다. 없으면 iOS 레이아웃 러너를 멈추지 않는다 (`hasActiveIOSRunners`·`stopAllIOSRunners()` 만 쓴다).
  var screenLayout: ScreenLayoutClientImpl?
  /// 녹화 저장·설치가 끝나기를 기다리는 중. 그동안 온 종료 요청은 거절한다 (기다림이 끝나면 앱이 스스로 종료한다).
  private var isWaitingToTerminate = false
  /// 녹화·설치를 기다리는 종료에서 러너 정리(5초 상한)를 이미 기다렸다. 다시 종료할 때 상한을 한 번 더 쓰지 않는다
  /// (그때까지 멈추지 않은 러너는 SIGTERM 을 받았거나 10분 유휴 제한으로 끝나고, 남은 앱은 다음 켜짐 정리가 지운다).
  private var didWaitForLayoutRunners = false

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
    // iOS·Android 어느 쪽이든 녹화 중이면 한 번만 묻는다 (문구가 두 플랫폼에 맞다).
    let isRecording = (self.launcherModel?.isRecording ?? false) || (self.androidDevicesModel?.isRecording ?? false)
    if isRecording {
      guard RecordingTerminationPrompt.confirmQuit() else { return .terminateCancel }
    }
    guard isRecording || setupAction != .terminateNow || androidAction != .terminateNow else {
      return self.stopLayoutRunnersThenTerminate()
    }
    self.waitThenTerminate()
    return .terminateCancel
  }

  /// 녹화·설치를 기다리지 않을 때: iOS 레이아웃 러너가 있으면 묻지 않고 멈춘 뒤 종료를 허락한다 (`.terminateLater`, 5초 상한).
  /// 없으면 곧바로 끝낸다.
  private func stopLayoutRunnersThenTerminate() -> NSApplication.TerminateReply {
    guard !self.didWaitForLayoutRunners, let screenLayout = self.screenLayout, screenLayout.hasActiveIOSRunners else {
      return .terminateNow
    }
    Task {
      await screenLayout.stopAllIOSRunners()
      NSApp.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  /// 종료가 정해졌다: 앱 로그 받기를 기다리지 않고 모두 멈춘다 (actor 를 거치지 않는 동기 호출이라 종료 전에 신호가 나간다).
  func applicationWillTerminate(_ notification: Notification) {
    self.appLog?.stopAll()
  }

  /// 녹화 저장(iOS·Android)·런타임 설치·Android 도구 설치·iOS 레이아웃 러너 정리의 종료 처리를 함께 시작하고, 모두 끝나기를
  /// 기다린 뒤 다시 종료한다. 기다릴 것이 없는 쪽은 종료 표시만 세우고 바로 끝난다.
  private func waitThenTerminate() {
    self.isWaitingToTerminate = true
    let launcher = self.launcherModel
    let androidDevices = self.androidDevicesModel
    let setup = self.setupModel
    let androidSetup = self.androidSetupModel
    let screenLayout = self.screenLayout
    // 다섯 모두 이 호출 안에서 첫 await 까지 동기로 돌아 녹화 멈춤·설치 취소·종료 표시를 함께 시작한다.
    // 하나를 기다리느라 다른 쪽 멈춤이 늦어지지 않게 하고(서로 공유 자원이 없다), 끝나기만 마지막에 모두 기다린다.
    let recording = Task.immediate { await launcher?.appTerminationRequested() }
    let androidRecording = Task.immediate { await androidDevices?.appTerminationRequested() }
    let runtime = Task.immediate { await setup?.appTerminationRequested() }
    let android = Task.immediate { await androidSetup?.appTerminationRequested() }
    let layoutRunners = Task.immediate { await screenLayout?.stopAllIOSRunners() }
    Task {
      await recording.value
      await androidRecording.value
      await runtime.value
      await android.value
      await layoutRunners.value
      self.didWaitForLayoutRunners = true
      self.isWaitingToTerminate = false
      NSApp.terminate(nil)
    }
  }
}
