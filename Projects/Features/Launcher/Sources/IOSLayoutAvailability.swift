import Core

/// 행 "레이아웃 보기"(레이아웃 창 열기)를 누를 수 있는지. 창을 여는 것은 View 이고(상태 없음), 읽기는 창이 맡는다.
/// 기기·작업 규칙은 스크린샷(`ScreenshotActivity.canStart`)과 같고, "찍는 중" 조건만 없다: 레이아웃 읽기는
/// 스크린샷·녹화와 겹쳐도 된다.
enum IOSLayoutAvailability {
  /// 기기 iOS 가 러너의 최소 버전(`IOSLayoutRunner.minimumOSVersion`) 보다 낮지 않으면 true.
  static func supportsRunner(_ device: VirtualDevice) -> Bool {
    device.runtime.version >= IOSLayoutRunner.minimumOSVersion
  }

  /// `screenshotAvailability == .allowed`(쓸 수 있고 켜짐)이고, 기기 iOS 가 러너의 최소 버전 이상이고(`supportsRunner`. 낮으면
  /// 러너가 돌지 않아 준비가 늘 실패한다), 기기 작업이 없거나 `.installApp`·`.openURL`·`.launchApp` 이면 true.
  /// 작업은 모든 케이스를 적는 허용 목록이다 (`default` 없음: 새 `DeviceTask` 케이스가 생기면 컴파일러가 여기서 멈춘다).
  static func canOpen(device: VirtualDevice, during task: DeviceTask?) -> Bool {
    guard device.screenshotAvailability == .allowed, self.supportsRunner(device) else { return false }
    return switch task {
    case .none, .installApp, .openURL, .launchApp: true
    case .boot, .shutdown, .delete, .erase: false
    }
  }
}
