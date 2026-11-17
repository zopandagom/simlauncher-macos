/// 로그 내보내기(클립보드·파일 쓰기) 실패. 화면 문구는 Feature 가 정한다.
/// `WorkspaceError` 와 따로 둔다: 스크린샷·녹화 문구가 `WorkspaceError` 를 전부 다루므로 뜻 없는 케이스를 떠안지 않게.
public enum WorkspaceExportError: Error, Hashable, Sendable {
  /// 클립보드에 쓰지 못했다.
  case clipboardUnavailable
  /// 그 위치에 쓸 권한이 없다.
  case noPermission
  /// 디스크 공간이 부족하다.
  case diskFull
  /// 읽기 전용 볼륨이다.
  case readOnlyVolume
  /// 고른 폴더가 없다 (패널을 닫은 뒤 옮겨지거나 지워짐).
  case folderNotFound
  /// 그 밖의 쓰기 실패 (그 이름이 폴더 등).
  case writeFailed
}
