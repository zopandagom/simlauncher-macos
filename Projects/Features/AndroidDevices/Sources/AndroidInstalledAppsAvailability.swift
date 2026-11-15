import Core

/// 행 "설치된 앱…"(설치된 앱 시트 열기)을 누를 수 있는지. 기기 규칙은 앱 작업과 같고(켜짐·쓸 수 있음,
/// `appActionAvailability`), 작업 규칙은 테스트 조건보다 좁다: 그 기기에 진행 작업이 하나도 없을 때만 연다. 설치와 삭제
/// (`adb install`·`uninstall`)가 겹치면 순서에 따라 앱이 남거나 사라지고(실측), 실행·링크 열기 중인 앱을 지우면 그 작업이 실패하기
/// 때문이다. 시트가 창을 막아 연 뒤에는 그 기기에 새 작업이 시작되지 않는다.
enum AndroidInstalledAppsAvailability {
  /// `appActionAvailability == .allowed`(쓸 수 있고 켜짐)이고 기기 작업이 없으면 true.
  /// 작업은 모든 케이스를 적는다 (`default` 없음: 새 `AndroidDeviceTask` 케이스가 생기면 컴파일러가 여기서 멈춘다).
  static func canOpen(device: AndroidVirtualDevice, during task: AndroidDeviceTask?) -> Bool {
    guard device.appActionAvailability == .allowed else { return false }
    return switch task {
    case .none: true
    case .installApp, .launchApp, .openURL, .boot, .shutdown, .delete, .erase: false
    }
  }
}
