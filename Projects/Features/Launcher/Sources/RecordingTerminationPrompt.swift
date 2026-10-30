import AppKit

/// 녹화 중(저장 중 포함) 앱 종료 요청을 확인하는 대화상자. App 이 종료 요청을 받았을 때 iOS·Android 기기 목록 어느 쪽이든 녹화 중이면
/// (`LauncherModel.isRecording`·`AndroidDevicesModel.isRecording`) 한 번 부른다.
@MainActor
public enum RecordingTerminationPrompt {
  /// 대화상자를 띄우고 사용자가 "저장하고 종료"를 골랐으면 true. 기본 버튼(Return)은 "취소"다.
  public static func confirmQuit() -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = LauncherText.recordingTerminationTitle
    alert.informativeText = LauncherText.recordingTerminationMessage
    alert.addButton(withTitle: LauncherText.cancelButton)
    alert.addButton(withTitle: LauncherText.saveAndQuitButton)
    return alert.runModal() == .alertSecondButtonReturn
  }
}
