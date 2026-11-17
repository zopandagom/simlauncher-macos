import Core
import Foundation

/// 사용자 폴더·클립보드와 Finder. Impl 은 `FileManager`(사진·동영상 폴더)·`NSPasteboard`·`NSWorkspace` 를 쓴다.
/// 스크린샷·녹화 예약은 파일을 덮어쓰지 않고, 로그 내보내기(`writeTextFile`)는 저장 패널이 확인한 파일만 바꾼다.
public protocol WorkspaceClient: Sendable {
  /// 사진 폴더의 `SimLauncher` 폴더를 준비하고(없으면 만든다) 그 안에 `name.fileName(attempt: 1)` 의 빈 파일을
  /// 독점 생성(이미 있으면 실패)으로 만들어 그 URL 을 돌려준다. 이미 있으면 attempt 2…`ScreenshotFileName.maxAttempts` 로 다시 시도하고,
  /// 모두 있으면 `.fileNameUnavailable`. 폴더를 만들 수 없거나(그 자리에 파일, 권한, 읽기 전용) 그 안에 쓸 수 없으면 `.folderUnavailable`.
  /// 예약한 빈 파일은 촬영이 덮어쓴다 (simctl 은 있는 파일을 덮어쓴다, 측정. Android 는 AndroidEmulator Impl 이
  /// `adb exec-out screencap` 출력을 그 파일에 쓴다: 만들지 않고 링크를 따라가지 않는다).
  /// `SimLauncher` 가 디렉터리를 가리키는 심볼릭 링크면 따라가 그 폴더에 만들고, 돌려주는 URL 은 링크 경로 아래다.
  func reserveScreenshotFile(_ name: ScreenshotFileName) async throws(WorkspaceError) -> URL

  /// 동영상 폴더의 `SimLauncher` 폴더를 준비하고 `name.fileName(attempt:)` 의 빈 파일을 독점 생성으로 예약해 그 URL 을 돌려준다.
  /// 규칙(번호·심볼릭 링크·오류)은 `reserveScreenshotFile` 과 같다. 예약한 빈 파일은 녹화(`recordVideo --force`)가 덮어쓴다
  /// (simctl 은 `--force` 없이는 있는 파일에 쓰지 않고 exit 17, 측정). Android 는 `adb pull` 이 그 자리에 새 파일로 바꿔 넣는다
  /// (inode 가 바뀐다, 실측). 가져오지 못하면 AndroidEmulator Impl 이 0바이트로 잘라 두어 `removeReservedFile` 이 지울 수 있다.
  func reserveRecordingFile(_ name: RecordingFileName) async throws(WorkspaceError) -> URL

  /// 예약한 파일을 지운다 (촬영·녹화 실패 때). 사진·동영상 폴더의 저장 폴더 바로 안의 **크기 0 인 일반 파일**만 지운다:
  /// 내용이 있는 파일(실패로 끝났어도 화면이 담긴 녹화 등)·폴더·심볼릭 링크(링크 자체를 본다)는 지우지 않는다.
  /// 파일이 없거나 지우지 못하면 무시한다.
  func removeReservedFile(_ file: URL) async

  /// Finder 를 앞으로 가져와 그 파일을 선택해 보인다. 파일이 없으면 Finder 를 열지 않고 `.fileNotFound`
  /// (`NSWorkspace.activateFileViewerSelecting` 은 결과를 돌려주지 않고 없는 파일에도 Finder 만 앞으로 가져온다, 측정).
  func revealInFinder(_ file: URL) async throws(WorkspaceError)

  /// 일반 클립보드(`NSPasteboard.general`)의 앞 내용을 지우고 글 하나(문자열 형식)를 그대로(제어 문자 포함) 쓴다.
  /// 메인에서 쓴다 (33.7 MB 에서 15~91ms, 측정). 쓰지 못하면(`setString` 이 거짓) `.clipboardUnavailable`.
  func copyToClipboard(_ text: String) async throws(WorkspaceExportError)

  /// 사용자가 저장 패널에서 고른 파일 URL 에 글을 UTF-8(BOM 없음)로 원자적으로 쓴다 (임시 파일에 쓴 뒤 바꿔 넣기, 메인 밖).
  /// 같은 이름이 있으면 바꾼다 — 덮어쓰기는 저장 패널이 이미 확인했다. 그 이름이 심볼릭 링크면 링크 자체가 일반 파일로 바뀌고
  /// 대상은 그대로다 (측정). 실패하면 원래 파일은 그대로이고 임시 파일도 남지 않는다 (디스크 가득 참 측정).
  /// 파일 URL 이 아니면 `.writeFailed`.
  func writeTextFile(_ text: String, to file: URL) async throws(WorkspaceExportError)
}
