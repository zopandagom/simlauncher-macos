import Core
import Foundation
import SimulatorInterface

/// 테스트 조건 시트의 앱 단위 구역(앱 고르기·권한·푸시 알림) 문구. "(공통)" 문구는 Android 기기 목록(AndroidDevices)에도 같은
/// 키·값으로 있다 (그쪽 `LauncherTextSyncTests` 가 확인한다).
extension LauncherText {
  // MARK: - 앱

  /// (공통) 앱 구역 제목이자 앱 고르기 Picker 이름.
  static var appSection: String {
    String(localized: "앱", bundle: .module)
  }

  /// (공통) 앱을 고르지 않은 Picker 값.
  static var noAppSelected: String {
    String(localized: "앱을 고르세요", bundle: .module)
  }

  /// 앱 고르기 항목: 표시 이름과 번들 ID (표시 이름이 같은 앱을 가른다). 둘 다 앱이 정한 글자라 번역하지 않는다.
  static func appPickerName(_ app: InstalledApp) -> String {
    String(localized: "\(app.displayName) (\(app.bundleID.rawValue))", bundle: .module)
  }

  /// (공통)
  static var readingApps: String {
    String(localized: "앱 목록을 읽는 중…", bundle: .module)
  }

  /// (공통)
  static var appsReadFailed: String {
    String(localized: "앱 목록을 읽지 못했습니다.", bundle: .module)
  }

  /// (공통)
  static var noInstalledAppsForConditions: String {
    String(localized: "이 기기에 설치한 앱이 없습니다. 앱을 설치한 뒤 앱 목록 다시 읽기를 누르세요.", bundle: .module)
  }

  /// (공통)
  static var refreshAppsButton: String {
    String(localized: "앱 목록 다시 읽기", bundle: .module)
  }

  /// (공통)
  static var appsRefreshNote: String {
    String(localized: "시트를 연 뒤 설치한 앱은 앱 목록 다시 읽기로 보입니다.", bundle: .module)
  }

  /// (공통) 앱을 고르지 않았을 때 권한·푸시 알림 구역의 한 줄.
  static var selectAppFirst: String {
    String(localized: "위에서 앱을 고르세요.", bundle: .module)
  }

  // MARK: - 권한

  /// (공통)
  static var privacySection: String {
    String(localized: "권한", bundle: .module)
  }

  /// `simctl privacy` 서비스 이름. 사진·연락처 무리 밖은 `privacyServiceDeviceName(_:)` 이 고른다.
  static func privacyServiceName(_ service: IOSPrivacyService) -> String {
    switch service {
    case .location: String(localized: "위치 (사용하는 동안)", bundle: .module)
    case .locationAlways: String(localized: "위치 (항상)", bundle: .module)
    case .camera, .microphone, .motion, .mediaLibrary: self.privacyServiceDeviceName(service)
    case .photos: String(localized: "사진", bundle: .module)
    case .photosAdd: String(localized: "사진 추가", bundle: .module)
    case .contacts: String(localized: "연락처", bundle: .module)
    case .calendar: String(localized: "캘린더", bundle: .module)
    case .reminders: String(localized: "미리 알림", bundle: .module)
    }
  }

  /// 기기 장치·미디어 서비스 이름 (`privacyServiceName(_:)` 가 부른다. 그 밖의 서비스는 그쪽 이름으로 돌려보낸다).
  private static func privacyServiceDeviceName(_ service: IOSPrivacyService) -> String {
    switch service {
    case .camera: String(localized: "카메라", bundle: .module)
    case .microphone: String(localized: "마이크", bundle: .module)
    case .motion: String(localized: "동작 및 피트니스", bundle: .module)
    case .mediaLibrary: String(localized: "미디어 및 Apple Music", bundle: .module)
    case .location, .locationAlways, .photos, .photosAdd, .contacts, .calendar, .reminders:
      self.privacyServiceName(service)
    }
  }

  /// 권한 동작 이름 (행의 "바꾸기" 메뉴 항목과 바꾼 값 기록).
  static func privacyActionName(_ action: IOSPrivacyAction) -> String {
    switch action {
    case .grant: String(localized: "허용", bundle: .module)
    case .revoke: String(localized: "거부", bundle: .module)
    case .reset: String(localized: "다시 묻기 (초기화)", bundle: .module)
    }
  }

  static var privacyChangeMenu: String {
    String(localized: "바꾸기", bundle: .module)
  }

  /// 행의 "바꾸기" 메뉴의 손쉬운 사용 이름 (어느 권한의 메뉴인지).
  static func privacyMenuAccessibilityLabel(_ service: IOSPrivacyService) -> String {
    String(localized: "\(self.privacyServiceName(service)) 권한 바꾸기", bundle: .module)
  }

  /// 권한 행 부제: SimLauncher 가 켜져 있는 동안 이 앱에 마지막으로 바꾼 값.
  static func privacyHistoryLine(_ action: IOSPrivacyAction) -> String {
    String(localized: "SimLauncher 가 바꾼 값: \(self.privacyActionName(action))", bundle: .module)
  }

  static var privacyStateNote: String {
    String(localized: "iOS 는 권한의 지금 상태를 알려 주지 않아, SimLauncher 가 켜져 있는 동안 바꾼 값만 보입니다.", bundle: .module)
  }

  static var privacyTerminationNote: String {
    String(
      localized: "위치 밖의 권한을 바꾸면 실행 중인 앱이 종료됩니다(값이 같아도). SimLauncher 로 실행해 로그를 받던 앱이면 로그도 끝납니다.",
      bundle: .module
    )
  }

  static var notificationPermissionNote: String {
    String(localized: "알림 권한은 바꿀 수 없습니다. 앱에서 알림을 허용하세요.", bundle: .module)
  }

  // MARK: - 푸시 알림

  /// (공통)
  static var pushSection: String {
    String(localized: "푸시 알림", bundle: .module)
  }

  static var pushInputLabel: String {
    String(localized: "입력 방식", bundle: .module)
  }

  static func pushInputName(_ mode: TestConditionsAppDraft.PushInputMode) -> String {
    switch mode {
    case .form: String(localized: "제목·본문", bundle: .module)
    case .json: String(localized: "JSON", bundle: .module)
    }
  }

  static var pushTitleField: String {
    String(localized: "제목 (선택)", bundle: .module)
  }

  static var pushBodyField: String {
    String(localized: "본문", bundle: .module)
  }

  /// JSON 입력 아래 바이트 수. simctl 은 보낸 바이트를 공백까지 그대로 센다.
  static func pushByteCount(_ count: Int) -> String {
    String(localized: "\(count) / \(PushPayload.maxByteCount) 바이트", bundle: .module)
  }

  static var sendPushButton: String {
    String(localized: "보내기", bundle: .module)
  }

  static var pushAuthorizationNote: String {
    String(
      localized: "앱이 알림 권한을 받아야 알림이 보입니다. 권한이 없으면 iOS 버전에 따라 '보냈습니다' 로 나와도 화면에 보이지 않을 수 있습니다.",
      bundle: .module
    )
  }

  /// JSON 예시의 제목 (예시 JSON 의 키 골격은 코드가 만든다: 번역이 JSON 을 깨뜨리지 못한다).
  static var pushExampleTitle: String {
    String(localized: "테스트 알림", bundle: .module)
  }

  static var pushExampleBody: String {
    String(localized: "SimLauncher 가 보낸 알림입니다.", bundle: .module)
  }

  /// 푸시 입력 문제. 폼의 빈 본문·JSON 공백뿐은 화면에 보이지 않는다 (버튼만 꺼진다).
  static func pushProblem(_ problem: PushPayloadProblem) -> String {
    switch problem {
    case .emptyBody:
      String(localized: "본문을 넣으세요.", bundle: .module)
    case .empty:
      String(localized: "JSON 을 넣으세요.", bundle: .module)
    case .notJSON:
      String(localized: "JSON 형식이 아닙니다. 괄호·따옴표·쉼표를 확인하세요.", bundle: .module)
    case .smartQuotes:
      String(localized: "따옴표가 “ ” 로 바뀌었습니다. 곧은 따옴표(\")로 바꾸세요.", bundle: .module)
    case .rootNotObject:
      String(localized: "JSON 의 맨 바깥은 { } 객체여야 합니다.", bundle: .module)
    case .missingAPS:
      String(localized: "JSON 에 aps 키가 있어야 합니다.", bundle: .module)
    case .apsNotObject:
      String(localized: "aps 값은 { } 객체여야 합니다.", bundle: .module)
    case .apsEmpty:
      String(localized: "aps 가 비어 있습니다. alert 같은 값을 넣으세요.", bundle: .module)
    case .alertInvalid:
      String(localized: "aps 의 alert 값은 글자나 { } 객체여야 합니다.", bundle: .module)
    case let .tooLarge(byteCount):
      String(
        localized: "알림 내용이 \(byteCount) 바이트입니다. \(PushPayload.maxByteCount) 바이트 이하로 줄이세요.",
        bundle: .module
      )
    }
  }

  // MARK: - 결과

  /// 마지막 권한 바꾸기·푸시 보내기의 성공 줄. 앱 이름은 명령을 시작한 때의 이름이다.
  static func testConditionsResult(_ result: TestConditionsResult) -> String {
    switch result {
    case let .privacyChanged(service, action, appName):
      String(
        localized: "\(appName) 앱의 \(self.privacyServiceName(service)) 권한을 바꿨습니다: \(self.privacyActionName(action))",
        bundle: .module
      )
    case let .pushSent(appName):
      String(localized: "\(appName) 앱에 알림을 보냈습니다.", bundle: .module)
    }
  }

  /// 푸시를 보냈지만 기기가 받지 않은 이유: 알림 권한 없음 또는 앱 없음 (iOS 27.0 에서 둘 다 exit 211, `IOSPushOutcome.notAuthorized`).
  static func pushNotAuthorized(appName: String) -> String {
    String(
      localized: "\(appName) 앱이 알림 권한을 받지 않았거나 기기에 없어 알림을 보일 수 없습니다. 앱에서 알림을 허용한 뒤 다시 보내세요. 앱을 지웠다면 앱 목록 다시 읽기를 누르세요.",
      bundle: .module
    )
  }

  static var pushNoVisibleContent: String {
    String(localized: "이 iOS 는 화면에 보일 내용(alert)이 없는 알림을 받지 않습니다. 제목이나 본문을 넣으세요.", bundle: .module)
  }

  static var pushRejected: String {
    String(localized: "기기가 알림 내용을 거절했습니다. JSON 의 aps 값을 확인하세요.", bundle: .module)
  }
}
