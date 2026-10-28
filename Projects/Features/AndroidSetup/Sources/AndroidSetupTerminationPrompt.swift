import AppKit

/// Android 도구 설치 중(받기·확인·풀기) 앱 종료 요청을 확인하는 대화상자. App 이 종료 요청을 받았을 때
/// `AndroidSetupModel.terminationAction` 이 `.confirmThenCancel` 이면 부른다.
@MainActor
public enum AndroidSetupTerminationPrompt {
  /// 대화상자를 띄우고 사용자가 "종료"를 골랐으면 true. 기본 버튼(Return)은 "계속 설치"다.
  public static func confirmQuit() -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = AndroidSetupText.terminationTitle
    alert.informativeText = AndroidSetupText.terminationMessage
    alert.addButton(withTitle: AndroidSetupText.continueInstallButton)
    alert.addButton(withTitle: AndroidSetupText.quitButton)
    return alert.runModal() == .alertSecondButtonReturn
  }
}
