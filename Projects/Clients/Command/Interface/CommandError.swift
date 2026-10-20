/// 명령 실행 실패. 0 이 아닌 종료 코드는 에러가 아니라 `CommandResult` 로 돌려준다.
public enum CommandError: Error, Equatable, Sendable {
  /// 프로세스를 시작하지 못했다 (실행 파일 없음·실행 권한 없음 등).
  case launchFailed
  /// `runCancellable` 만 던진다: Task 가 취소되어 프로세스를 멈췄다 (끝난 뒤 던진다).
  /// 시작 전에 이미 취소됐으면 실행하지 않고 던진다.
  case cancelled
  /// `runCancellable` 만 던진다: 시간 제한이 지나 프로세스를 멈췄다 (끝난 뒤 던진다).
  case timedOut
}
