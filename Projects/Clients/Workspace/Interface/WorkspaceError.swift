/// Workspace 작업 실패. 화면 문구는 Feature 가 정한다.
public enum WorkspaceError: Error, Hashable, Sendable {
  /// 저장 폴더(사진·동영상 폴더의 `SimLauncher`)를 만들 수 없거나 그 안에 파일을 만들 수 없다
  /// (사진·동영상 폴더를 찾지 못함, 그 자리에 같은 이름의 파일, 권한, 읽기 전용 볼륨, 디스크 가득 참 등).
  case folderUnavailable
  /// 번호를 붙인 이름까지 모두 이미 있다.
  case fileNameUnavailable
  /// 보일 파일이 없다 (저장 뒤 옮겨지거나 지워짐).
  case fileNotFound
}
