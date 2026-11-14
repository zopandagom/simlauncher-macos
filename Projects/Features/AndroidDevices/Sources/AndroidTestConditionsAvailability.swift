import Core

/// 행 "테스트 조건…"(테스트 조건 시트 열기)을 누를 수 있는지. 기기·작업 규칙은 레이아웃 보기(`AndroidLayoutAvailability`)와 같다:
/// 테스트 조건 명령(`cmd uimode`·`emu geo fix`)은 스크린샷·녹화와 겹쳐도 된다.
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
