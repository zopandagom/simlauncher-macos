import Core

/// 행 "테스트 조건…"(테스트 조건 시트 열기)을 누를 수 있는지. 기기·작업 규칙은 레이아웃 보기(`AndroidLayoutAvailability`)와 같다:
/// 테스트 조건 명령(`cmd uimode`·`emu geo fix`·`pm grant`·`pm revoke`·`pm clear-permission-flags`·`dumpsys package`, 앱 목록
/// `pm list packages`)은 스크린샷·녹화와 겹쳐도 된다. 권한 명령은 설치·실행 중에도 허용한다 (허용된 권한을 거부하면 그 앱이 종료된다:
/// 바꾸기 전에 묻지 않고 시트가 그 행에 안내한다).
enum AndroidTestConditionsAvailability {
  /// `appActionAvailability == .allowed`(쓸 수 있고 켜짐)이고 기기 작업이 없거나 `.installApp`·`.launchApp`·`.openURL` 이면 true.
  /// 작업은 모든 케이스를 적는 허용 목록이다 (`default` 없음: 새 `AndroidDeviceTask` 케이스가 생기면 컴파일러가 여기서 멈춘다).
  static func canOpen(device: AndroidVirtualDevice, during task: AndroidDeviceTask?) -> Bool {
    guard device.appActionAvailability == .allowed else { return false }
    return switch task {
    case .none, .installApp, .launchApp, .openURL: true
    case .boot, .shutdown, .delete, .erase: false
    }
  }
}
