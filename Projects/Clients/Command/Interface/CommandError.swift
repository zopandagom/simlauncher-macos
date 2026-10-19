/// 명령 실행 실패. 0 이 아닌 종료 코드는 에러가 아니라 `CommandResult` 로 돌려준다.
public enum CommandError: Error, Equatable, Sendable {
  /// 프로세스를 시작하지 못했다 (실행 파일 없음·실행 권한 없음 등).
  case launchFailed
}
