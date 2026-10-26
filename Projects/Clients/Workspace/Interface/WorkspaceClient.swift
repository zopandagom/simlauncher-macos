import Core
import Foundation

/// 사용자 폴더와 Finder. Impl 은 `FileManager`(사진 폴더)와 `NSWorkspace` 를 쓰고 파일을 덮어쓰지 않는다.
public protocol WorkspaceClient: Sendable {
  /// 사진 폴더의 `SimLauncher` 폴더를 준비하고(없으면 만든다) 그 안에 `name.fileName(attempt: 1)` 의 빈 파일을
  /// 독점 생성(이미 있으면 실패)으로 만들어 그 URL 을 돌려준다. 이미 있으면 attempt 2…`ScreenshotFileName.maxAttempts` 로 다시 시도하고,
  /// 모두 있으면 `.fileNameUnavailable`. 폴더를 만들 수 없거나(그 자리에 파일, 권한, 읽기 전용) 그 안에 쓸 수 없으면 `.folderUnavailable`.
  /// 예약한 빈 파일은 촬영이 덮어쓴다 (simctl 은 있는 파일을 덮어쓴다, 측정).
  /// `SimLauncher` 가 디렉터리를 가리키는 심볼릭 링크면 따라가 그 폴더에 만들고, 돌려주는 URL 은 링크 경로 아래다.
  func reserveScreenshotFile(_ name: ScreenshotFileName) async throws(WorkspaceError) -> URL

  /// `reserveScreenshotFile` 이 돌려준 파일을 지운다 (촬영 실패 때). 저장 폴더 바로 안의 파일이 아니면 지우지 않는다. 실패는 무시한다.
  func removeReservedFile(_ file: URL) async

  /// Finder 를 앞으로 가져와 그 파일을 선택해 보인다. 파일이 없으면 Finder 를 열지 않고 `.fileNotFound`
  /// (`NSWorkspace.activateFileViewerSelecting` 은 결과를 돌려주지 않고 없는 파일에도 Finder 만 앞으로 가져온다, 측정).
  func revealInFinder(_ file: URL) async throws(WorkspaceError)
}
