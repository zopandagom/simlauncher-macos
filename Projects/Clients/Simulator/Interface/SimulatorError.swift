/// 시뮬레이터 작업 실패. 화면 문구는 Feature 가 케이스별로 정하고, 명령 원문은 담지 않는다.
public enum SimulatorError: Error, Hashable, Sendable {
  /// xcrun·simctl 을 쓸 수 없다: Xcode 없음, Command Line Tools 만 있음, DEVELOPER_DIR 경로 없음, xcode-select 실패.
  case developerToolsUnavailable
  /// UDID 형식이 아니거나 simctl 이 "Invalid device" 로 답했다.
  case deviceNotFound
  /// 개발자 디렉터리에서 Simulator 앱을 찾지 못했다.
  case simulatorAppNotFound
  /// simctl 출력(JSON)을 해석하지 못했다.
  case unexpectedOutput
  /// 그 밖의 실패.
  case commandFailed
}
