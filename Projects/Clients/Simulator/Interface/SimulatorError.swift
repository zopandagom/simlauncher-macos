/// 시뮬레이터 작업 실패. 화면 문구는 Feature 가 케이스별로 정하고, 명령 원문은 담지 않는다.
public enum SimulatorError: Error, Hashable, Sendable {
  /// xcrun·simctl 을 쓸 수 없다: Xcode 없음, Command Line Tools 만 있음, DEVELOPER_DIR 경로 없음, xcode-select 실패.
  case developerToolsUnavailable
  /// UDID 형식이 아니거나, simctl 이 "Invalid device" 로 답했거나, 삭제·초기화 사전 확인에서 목록에 없다.
  case deviceNotFound
  /// 기기가 꺼져 있지 않아 지우거나 초기화하지 않았다 (사전 확인. erase 의 "in current state: Booted" 는 분류하지 않는다).
  case deviceNotShutdown
  /// 고른 런타임·기기 종류로 만들 수 없다: 목록에 없거나, 런타임을 쓸 수 없거나, 지원하지 않는 조합.
  /// simctl "Invalid device type"·"Invalid runtime"·"Incompatible device" 도 여기 든다.
  case creationOptionUnavailable
  /// 기기 이름이 `DeviceName.problem` 검사를 통과하지 못해 실행하지 않았다.
  case invalidDeviceName
  /// 개발자 디렉터리에서 Simulator 앱을 찾지 못했다.
  case simulatorAppNotFound
  /// simctl 출력(JSON)을 해석하지 못했다.
  case unexpectedOutput
  /// 그 밖의 실패.
  case commandFailed
}
