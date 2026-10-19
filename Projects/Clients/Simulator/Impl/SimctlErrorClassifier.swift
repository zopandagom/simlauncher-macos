import SimulatorInterface

/// 실패한 명령의 종료 코드·stderr 를 `SimulatorError` 로 바꾼다 (순수). 원문은 담지 않는다.
enum SimctlErrorClassifier {
  static func error(exitCode: Int32, stderr: String) -> SimulatorError {
    // xcrun 자신의 오류(simctl 없음, DEVELOPER_DIR 경로 없음 등). 종료 코드는 72·1 등 여러 가지라 보지 않는다.
    // simctl 자체 오류("Invalid device…", "An error was encountered…")는 이 접두어로 시작하지 않는다.
    if stderr.drop(while: \.isWhitespace).hasPrefix("xcrun: error:") {
      return .developerToolsUnavailable
    }
    // 없는 기기: boot 는 "Invalid device or device pair: …", shutdown 은 "Invalid device: …" (종료 코드 148).
    if stderr.contains("Invalid device") {
      return .deviceNotFound
    }
    // "Unable to … in current state" (149) 도 여기 든다. boot·shutdown 은 그 전에 재조회로 성공 여부를 판정한다.
    return .commandFailed
  }
}
