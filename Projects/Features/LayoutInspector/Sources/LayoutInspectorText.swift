import Foundation

/// 레이아웃 창 문구. 모두 이 모듈의 `Localizable.xcstrings` 에서 찾는다 (`bundle: .module`).
/// 기기 이름·앱 식별자·노드의 종류·식별자·텍스트와 숫자 값(`LayoutValueFormat`)은 여기를 거치지 않고 그대로 보인다.
enum LayoutInspectorText {
  // MARK: - 창 위

  static func windowTitle(deviceName: String) -> String {
    String(localized: "\(deviceName) 레이아웃", bundle: .module)
  }

  static var refreshButton: String {
    String(localized: "새로 고침", bundle: .module)
  }

  static var refreshHelp: String {
    String(localized: "기기의 지금 화면을 다시 읽습니다. 화면이 바뀌어도 저절로 따라가지 않습니다.", bundle: .module)
  }

  static var retryButton: String {
    String(localized: "다시 시도", bundle: .module)
  }

  static func lastUpdated(_ date: Date) -> String {
    let time = date.formatted(date: .omitted, time: .standard)
    return String(localized: "마지막 갱신 \(time)", bundle: .module)
  }

  /// 새로 고침이 실패했을 때 배너에 붙이는, 지금 보이는 스냅샷의 시각.
  static func lastScreen(_ date: Date) -> String {
    let time = date.formatted(date: .omitted, time: .standard)
    return String(localized: "마지막 화면: \(time)", bundle: .module)
  }

  // MARK: - 읽는 중

  static var reading: String {
    String(localized: "화면을 읽는 중…", bundle: .module)
  }

  static var preparing: String {
    String(localized: "처음 한 번 레이아웃 보기를 준비하고 있습니다. 1분쯤 걸릴 수 있습니다…", bundle: .module)
  }

  // MARK: - 캔버스

  static var canvasAccessibilityLabel: String {
    String(localized: "화면 레이아웃", bundle: .module)
  }

  static var noNodes: String {
    String(localized: "읽은 뷰가 없습니다.", bundle: .module)
  }

  static var systemScreen: String {
    String(
      localized: "잠금 화면이나 알림 창 같은 시스템 화면의 레이아웃입니다. 앱을 보려면 기기에서 앱을 앞으로 가져온 뒤 새로 고치세요.",
      bundle: .module
    )
  }

  // MARK: - 옆 목록·속성

  static var stackTitle: String {
    String(localized: "이 위치의 뷰", bundle: .module)
  }

  static var detailTitle: String {
    String(localized: "속성", bundle: .module)
  }

  static var typeLabel: String {
    String(localized: "종류", bundle: .module)
  }

  static var identifierLabel: String {
    String(localized: "식별자", bundle: .module)
  }

  static var textLabel: String {
    String(localized: "텍스트", bundle: .module)
  }

  static var descriptionLabel: String {
    String(localized: "설명", bundle: .module)
  }

  static var widthLabel: String {
    String(localized: "너비", bundle: .module)
  }

  static var heightLabel: String {
    String(localized: "높이", bundle: .module)
  }

  static var noPickGuide: String {
    String(localized: "화면을 클릭해 뷰를 고르세요", bundle: .module)
  }

  static var densityUnavailable: String {
    String(localized: "화면 밀도를 읽지 못해 px 로만 보입니다.", bundle: .module)
  }

  // MARK: - 실패

  static func failure(_ failure: LayoutInspectorFailure) -> String {
    switch failure {
    case .xcodeUnavailable, .setupFailed, .appNotInForeground, .unsupported:
      self.platformFailure(failure)
    default:
      self.readFailure(failure)
    }
  }

  private static func readFailure(_ failure: LayoutInspectorFailure) -> String {
    switch failure {
    case .deviceGone:
      String(localized: "기기를 찾을 수 없거나 지금 쓸 수 없습니다. 메인 창의 기기 목록을 확인하세요.", bundle: .module)
    case .deviceNotBooted:
      String(localized: "기기가 켜져 있지 않습니다. 기기를 켠 뒤 새로 고치세요.", bundle: .module)
    case .toolsUnavailable:
      String(localized: "Android 도구(adb)를 쓸 수 없습니다. 메인 창의 Android 화면에서 도구 상태를 확인하세요.", bundle: .module)
    case .screenNotIdle:
      String(localized: "화면이 계속 바뀌고 있어(애니메이션·동영상 등) 레이아웃을 읽지 못했습니다. 화면이 멈춘 뒤 새로 고치세요.", bundle: .module)
    case .displayOff:
      String(localized: "기기 화면이 꺼져 있습니다. 에뮬레이터 창의 전원 버튼으로 화면을 켠 뒤 새로 고치세요.", bundle: .module)
    case .automationBusy:
      String(
        localized: "다른 도구가 이 기기의 화면 정보를 읽고 있어 레이아웃을 읽지 못했습니다. UI 테스트 같은 자동화 도구를 멈춘 뒤 새로 고치세요.",
        bundle: .module
      )
    case .timedOut:
      String(localized: "기기가 제때 답하지 않았습니다. 잠시 뒤 새로 고치세요.", bundle: .module)
    default:
      String(localized: "화면 정보를 읽지 못했습니다. 다시 시도하세요.", bundle: .module)
    }
  }

  private static func platformFailure(_ failure: LayoutInspectorFailure) -> String {
    switch failure {
    case .unsupported:
      String(localized: "이 기기의 레이아웃 보기는 아직 지원하지 않습니다.", bundle: .module)
    case .xcodeUnavailable:
      String(localized: "Xcode 가 준비되지 않아 iOS 레이아웃을 읽을 수 없습니다. 메인 창의 개발 환경에서 Xcode 를 확인하세요.", bundle: .module)
    case .setupFailed:
      String(localized: "iOS 레이아웃 보기를 준비하지 못했습니다. 다시 시도하세요.", bundle: .module)
    default:
      String(localized: "기기에 앞에 떠 있는 앱이 없습니다. 볼 앱을 띄운 뒤 새로 고치세요.", bundle: .module)
    }
  }
}
