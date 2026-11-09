import AppLogInterface
import Core
import Foundation

/// 로그 창 문구. 모두 이 모듈의 `Localizable.xcstrings` 에서 찾는다 (`bundle: .module`).
/// 앱 출력·기기 이름·앱 이름은 여기를 거치지 않고 그대로 보이거나 보간 인자로 들어간다.
enum DeviceLogText {
  // MARK: - 창 위

  static func windowTitle(deviceName: String) -> String {
    String(localized: "\(deviceName) 로그", bundle: .module)
  }

  static var defaultWindowTitle: String {
    String(localized: "앱 로그", bundle: .module)
  }

  static var appPickerLabel: String {
    String(localized: "앱", bundle: .module)
  }

  /// 앱 고르기의 항목: 앱 이름 · 시작 시각 · 상태.
  static func sessionLabel(appName: String, startedAt: Date, state: AppLogSessionState) -> String {
    let time = startedAt.formatted(date: .omitted, time: .standard)
    let status = self.shortState(state)
    return String(localized: "\(appName) · 시작 \(time) · \(status)", bundle: .module)
  }

  static func shortState(_ state: AppLogSessionState) -> String {
    switch state {
    case .receiving: self.receiving
    case .ended: String(localized: "끝남", bundle: .module)
    }
  }

  static var receiving: String {
    String(localized: "받는 중", bundle: .module)
  }

  /// 상태 글자. 끝났으면 이유를 붙인다. Android 의 `.deviceShutDown` 은 adb 연결이 끊긴 경우도 포함해 문구가 다르다.
  static func state(_ state: AppLogSessionState, platform: AppLogTarget.Platform) -> String {
    switch state {
    case .receiving:
      self.receiving
    case .ended(.appExited):
      String(localized: "끝남 — 앱이 끝났습니다", bundle: .module)
    case .ended(.deviceShutDown):
      switch platform {
      case .iOS: String(localized: "끝남 — 기기가 꺼졌습니다", bundle: .module)
      case .android: String(localized: "끝남 — 기기가 꺼졌거나 연결이 끊겼습니다", bundle: .module)
      }
    case .ended(.replaced):
      String(localized: "끝남 — SimLauncher 가 앱을 다시 설치·실행했습니다", bundle: .module)
    case .ended(.stopped):
      String(localized: "끝남 — 로그 받기를 멈췄습니다", bundle: .module)
    }
  }

  static var relaunchButton: String {
    String(localized: "다시 실행", bundle: .module)
  }

  static var relaunchHelp: String {
    String(localized: "켜진 기기에서 이 앱을 다시 실행하고 새 로그를 받습니다. 기기를 켜지는 않습니다.", bundle: .module)
  }

  /// 다시 실행 실패 문구. 개발 도구 문구만 플랫폼별이고, Android 전용 케이스는 iOS 에서 나오지 않아 플랫폼을 보지 않는다.
  static func relaunchFailed(_ error: AppLogLaunchError, platform: AppLogTarget.Platform) -> String {
    switch error {
    case .developerToolsUnavailable:
      self.developerToolsUnavailable(platform: platform)
    case .deviceUnavailable:
      String(localized: "이 기기를 지금 쓸 수 없어 다시 실행하지 못했습니다. 기기 목록에서 이유를 확인하세요.", bundle: .module)
    case .noLauncherActivity:
      String(localized: "이 앱에는 홈 화면에서 여는 화면이 없어 실행할 수 없습니다.", bundle: .module)
    case .adbUnavailable:
      String(localized: "기기 상태를 확인하지 못했습니다. 잠시 뒤 다시 시도하세요.", bundle: .module)
    case .deviceNotFound:
      String(localized: "기기를 찾지 못해 다시 실행하지 못했습니다. 기기 목록에 이 기기가 있는지 확인하세요.", bundle: .module)
    case .deviceNotBooted:
      String(localized: "기기가 꺼져 있어 다시 실행하지 않았습니다. 기기 목록에서 켠 뒤 다시 실행하세요.", bundle: .module)
    case .appNotInstalled:
      String(localized: "기기에 이 앱이 없습니다. 기기 목록에서 다시 설치하세요.", bundle: .module)
    case .appLaunchFailed:
      String(
        localized: "앱이 시작되지 않았거나 시작하자마자 종료되었습니다. 다시 실행해 보고, 계속되면 앱 개발자에게 알려 주세요.",
        bundle: .module
      )
    case .commandFailed:
      String(localized: "다시 실행하지 못했습니다. 잠시 뒤 다시 시도하세요.", bundle: .module)
    case .sessionNotFound:
      String(
        localized: "이 실행의 기록이 정리되어 다시 실행할 수 없습니다. 기기 목록에서 앱을 다시 설치하세요.",
        bundle: .module
      )
    }
  }

  private static func developerToolsUnavailable(platform: AppLogTarget.Platform) -> String {
    switch platform {
    case .iOS:
      String(
        localized: "Xcode 를 찾지 못했거나 아직 준비되지 않아 다시 실행하지 못했습니다. 메인 창 오른쪽 위 개발 환경을 눌러 준비를 마친 뒤 다시 시도하세요.",
        bundle: .module
      )
    case .android:
      String(
        localized: "Android 도구를 찾지 못해 다시 실행하지 못했습니다. 메인 창 Android 칸 오른쪽 위 Android 도구에서 상태를 확인하세요.",
        bundle: .module
      )
    }
  }

  static var noSessions: String {
    String(localized: "이 기기의 로그가 없습니다", bundle: .module)
  }

  static var noSessionsGuide: String {
    String(localized: "SimLauncher 에서 앱을 설치·실행하면 그때부터의 로그가 여기에 쌓입니다.", bundle: .module)
  }

  static var noMatchingLines: String {
    String(localized: "필터에 맞는 줄이 없습니다", bundle: .module)
  }

  // MARK: - 필터

  static func kind(_ kind: LogFilter.Kind) -> String {
    switch kind {
    case .contains: String(localized: "포함", bundle: .module)
    case .prefix: String(localized: "시작", bundle: .module)
    case .regex: String(localized: "정규식", bundle: .module)
    }
  }

  static var kindLabel: String {
    String(localized: "맞추는 방법", bundle: .module)
  }

  static var conditionPrompt: String {
    String(localized: "걸러 볼 글자", bundle: .module)
  }

  static var excludeToggle: String {
    String(localized: "제외", bundle: .module)
  }

  static var excludeHelp: String {
    String(localized: "켜면 이 조건에 맞는 줄을 숨깁니다.", bundle: .module)
  }

  static var removeCondition: String {
    String(localized: "조건 지우기", bundle: .module)
  }

  static var addCondition: String {
    String(localized: "조건 더하기", bundle: .module)
  }

  static var caseSensitiveToggle: String {
    String(localized: "대소문자 구분", bundle: .module)
  }

  static var invalidRegex: String {
    String(localized: "정규식을 읽을 수 없습니다. 바로 앞 결과를 보이고 있습니다.", bundle: .module)
  }

  /// 필터 도움말. iOS: 여러 줄 print 는 줄마다 따로 오고 머리말이 없다 (2026-11-03 실측).
  /// Android: "시작" 은 threadtime 머리말(시각·pid·tid·레벨) 뒤 태그부터 비교한다 (`LogLineHeader`).
  static func filterHelp(platform: AppLogTarget.Platform) -> String {
    switch platform {
    case .iOS:
      String(
        // 키가 한 줄 길이 제한을 넘어 줄 끝 `\` 로 이어 쓴다 (키는 한 줄이다).
        localized: """
        포함 조건은 하나라도 맞으면 보이고, 제외 조건이 맞으면 숨깁니다. 여러 줄 print 는 줄마다 따로 걸러집니다\
        (Logger·NSLog 머리말은 첫 줄에만 붙습니다). '시작' 은 머리말 뒤 메시지와 비교합니다.
        """,
        bundle: .module
      )
    case .android:
      String(
        localized: """
        포함 조건은 하나라도 맞으면 보이고, 제외 조건이 맞으면 숨깁니다. \
        '시작' 은 시각·pid·tid·레벨 뒤의 태그부터 비교합니다.
        """,
        bundle: .module
      )
    }
  }

  // MARK: - 창 아래

  static func lineCounts(visible: Int, total: Int) -> String {
    String(localized: "보이는 \(visible)줄 / 전체 \(total)줄", bundle: .module)
  }

  static func discarded(_ count: Int) -> String {
    String(localized: "버퍼가 차서 앞 \(count)줄을 버렸습니다", bundle: .module)
  }

  static func newWhilePaused(_ count: Int) -> String {
    String(localized: "새 줄 \(count)", bundle: .module)
  }

  static var pauseButton: String {
    String(localized: "일시정지", bundle: .module)
  }

  static var resumeButton: String {
    String(localized: "계속", bundle: .module)
  }

  static var followToggle: String {
    String(localized: "따라가기", bundle: .module)
  }

  static var followHelp: String {
    String(
      localized: "켜면 새 줄이 올 때 맨 아래로 스크롤합니다. 위로 스크롤하면 꺼지고 맨 아래로 내리면 다시 켜집니다.",
      bundle: .module
    )
  }

  static var clearButton: String {
    String(localized: "지우기", bundle: .module)
  }

  static var clearHelp: String {
    String(localized: "지금까지 받은 줄을 창에서 지웁니다. 앱과 로그 받기는 계속됩니다.", bundle: .module)
  }
}
