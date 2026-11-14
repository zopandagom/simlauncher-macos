import Core

/// 행 "테스트 조건…"(테스트 조건 시트 열기)을 누를 수 있는지. 기기·작업 규칙은 스크린샷(`ScreenshotActivity.canStart`)과 같고,
/// "찍는 중" 조건만 없다: 테스트 조건 명령(`simctl ui`·`location`)은 스크린샷·녹화와 다른 하위 명령이라 겹쳐도 된다.
enum TestConditionsAvailability {
  /// `screenshotAvailability == .allowed`(쓸 수 있고 켜짐)이고, 기기 작업이 없거나 `.installApp`·`.openURL`·`.launchApp` 이면 true.
  /// 작업은 모든 케이스를 적는 허용 목록이다 (`default` 없음: 새 `DeviceTask` 케이스가 생기면 컴파일러가 여기서 멈춘다).
  static func canOpen(device: VirtualDevice, during task: DeviceTask?) -> Bool {
    guard device.screenshotAvailability == .allowed else { return false }
    return switch task {
    case .none, .installApp, .openURL, .launchApp: true
    case .boot, .shutdown, .delete, .erase: false
    }
  }
}
