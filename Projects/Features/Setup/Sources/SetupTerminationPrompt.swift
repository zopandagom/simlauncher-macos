import AppKit

/// 런타임 설치 중(준비·내려받기) 앱 종료 요청을 확인하는 대화상자. App 이 종료 요청을 받았을 때
/// `SetupModel.terminationAction` 이 `.confirmThenCancel` 이면 부른다.
@MainActor
public enum SetupTerminationPrompt {
  /// 대화상자를 띄우고 사용자가 "종료"를 골랐으면 true. 기본 버튼(Return)은 "계속 설치"다.
  public static func confirmQuit() -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = SetupText.terminationTitle
    alert.informativeText = SetupText.terminationMessage
    alert.addButton(withTitle: SetupText.continueInstallButton)
    alert.addButton(withTitle: SetupText.quitButton)
    return alert.runModal() == .alertSecondButtonReturn
  }
}
