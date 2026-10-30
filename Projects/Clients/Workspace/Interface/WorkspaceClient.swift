import Core
import Foundation

/// 사용자 폴더와 Finder. Impl 은 `FileManager`(사진·동영상 폴더)와 `NSWorkspace` 를 쓰고 파일을 덮어쓰지 않는다.
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
}
