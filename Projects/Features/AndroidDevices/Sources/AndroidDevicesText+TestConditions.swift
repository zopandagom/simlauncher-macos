import AndroidEmulatorInterface
import Core
import Foundation

/// 테스트 조건("테스트 조건…" 시트) 문구. "(공통)" 문구는 iOS 기기 목록(Launcher)의 `LauncherText+TestConditions.swift` 와 같은
/// 키·값이다 (`LauncherTextSyncTests` 가 확인한다).
extension AndroidDevicesText {
  // MARK: - 기기 행

  /// (공통)
  static var testConditionsButton: String {
    String(localized: "테스트 조건…", bundle: .module)
  }

  static var testConditionsHelp: String {
    String(localized: "외관·위치 같은 테스트 조건을 바꿉니다.", bundle: .module)
  }

  /// (공통) "테스트 조건…" 버튼이 막힌 이유 (툴팁). 기기 규칙은 스크린샷과 같다 (켜는 중은 `.notBooted`).
  static func testConditionsBlockReason(_ reason: AndroidAppActionBlockReason) -> String {
    switch reason {
    case .notBooted:
      String(localized: "켜진 기기에서만 테스트 조건을 바꿀 수 있습니다. 기기를 켠 뒤 다시 시도하세요", bundle: .module)
    case .unavailable:
      String(localized: "사용할 수 없는 기기에서는 테스트 조건을 바꿀 수 없습니다", bundle: .module)
    }
  }

  // MARK: - 시트

  /// (공통) 시트 제목. 기기 이름은 번역하지 않는 값이다.
  static func testConditionsSheetTitle(for device: AndroidDeviceLabel) -> String {
    String(localized: "\(device.name) 테스트 조건", bundle: .module)
  }

  /// (공통)
  static var testConditionsSheetNote: String {
    String(localized: "바꾼 조건은 기기에 바로 적용되고, 시트를 닫거나 SimLauncher 를 꺼도 기기에 남습니다.", bundle: .module)
  }

  /// (공통)
  static var displaySection: String {
    String(localized: "화면", bundle: .module)
  }

  /// (공통)
  static var appearanceLabel: String {
    String(localized: "외관", bundle: .module)
  }

  /// (공통)
  static func appearanceName(_ appearance: DeviceAppearance) -> String {
    switch appearance {
    case .light: String(localized: "라이트", bundle: .module)
    case .dark: String(localized: "다크", bundle: .module)
    }
  }

  /// (공통)
  static var readingConditions: String {
    String(localized: "지금 값을 읽는 중…", bundle: .module)
  }

  /// (공통) 읽기 실패 제목이자 외관을 읽지 못했을 때(`.unknown`)의 보조 문구.
  static var conditionsReadFailed: String {
    String(localized: "지금 값을 읽지 못했습니다.", bundle: .module)
  }

  /// (공통)
  static var rereadButton: String {
    String(localized: "다시 읽기", bundle: .module)
  }

  /// 외관이 자동·예약 모드(`.other`)일 때의 보조 문구.
  static var nightModeOtherNote: String {
    String(localized: "지금은 자동·예약 모드입니다. 라이트·다크를 고르면 바뀝니다.", bundle: .module)
  }

  /// (공통)
  static var applyingCondition: String {
    String(localized: "적용하는 중…", bundle: .module)
  }

  // MARK: - 위치

  /// (공통)
  static var locationSection: String {
    String(localized: "위치", bundle: .module)
  }

  /// (공통)
  static var coordinateField: String {
    String(localized: "위도, 경도", bundle: .module)
  }

  /// (공통)
  static var coordinatePlaceholder: String {
    String(localized: "예: 37.5665, 126.9780", bundle: .module)
  }

  /// (공통)
  static var locationPresetsMenu: String {
    String(localized: "자주 쓰는 위치", bundle: .module)
  }

  /// (공통)
  static func presetName(_ preset: LocationPreset) -> String {
    switch preset {
    case .seoul: String(localized: "서울", bundle: .module)
    case .tokyo: String(localized: "도쿄", bundle: .module)
    case .cupertino: String(localized: "쿠퍼티노", bundle: .module)
    case .newYork: String(localized: "뉴욕", bundle: .module)
    case .london: String(localized: "런던", bundle: .module)
    case .sydney: String(localized: "시드니", bundle: .module)
    }
  }

  /// (공통)
  static var setPointButton: String {
    String(localized: "이 위치로 설정", bundle: .module)
  }

  static var routeUnsupportedNote: String {
    String(
      localized: "Android 기기는 경로·시나리오를 지원하지 않습니다. 에뮬레이터 창의 ⋯ > Location 에서 경로를 재생할 수 있습니다.",
      bundle: .module
    )
  }

  static var locationServiceOffNote: String {
    String(localized: "기기의 위치 서비스가 꺼져 있어 앱이 위치를 받지 못합니다. 기기 설정 > 위치에서 켜세요.", bundle: .module)
  }

  /// (공통) 마지막으로 보낸 위치 줄. 시각과 내용(위도, 경도).
  static func sentLocationLine(_ sent: AndroidSentLocation) -> String {
    let time = sent.sentAt.formatted(date: .omitted, time: .standard)
    let content = self.coordinateText(sent.coordinate)
    return String(localized: "SimLauncher 가 마지막으로 보낸 위치 (\(time)): \(content)", bundle: .module)
  }

  /// (공통) 위도, 경도. 숫자는 로캘과 관계없이 마침표 소수점이다 (입력란과 같은 형식).
  static func coordinateText(_ coordinate: GeoCoordinate) -> String {
    let latitude = GeoCoordinate.decimalString(coordinate.latitude)
    let longitude = GeoCoordinate.decimalString(coordinate.longitude)
    return String(localized: "\(latitude), \(longitude)", bundle: .module)
  }

  /// (공통)
  static var sentLocationNote: String {
    String(
      localized: "기기에서 지금 위치를 읽을 수 없어 SimLauncher 가 보낸 기록만 보입니다. 다른 도구로 바꾸면 달라질 수 있습니다.",
      bundle: .module
    )
  }

  /// (공통) 기록은 기기를 끄거나 초기화해도 지우지 않는다.
  static var sentLocationKeptNote: String {
    String(localized: "기기를 끄거나 초기화해도 이 기록은 남습니다.", bundle: .module)
  }

  /// (공통) 좌표 입력 문제. 빈 입력은 문구를 보이지 않는다 (호출하지 않는다).
  static func coordinateProblem(_ problem: GeoCoordinateProblem) -> String {
    switch problem {
    case .empty, .format:
      String(localized: "위도, 경도를 숫자로 넣으세요. 소수점은 마침표(.)입니다.", bundle: .module)
    case .latitudeOutOfRange:
      String(localized: "위도는 -90 에서 90 사이여야 합니다.", bundle: .module)
    case .longitudeOutOfRange:
      String(localized: "경도는 -180 에서 180 사이여야 합니다.", bundle: .module)
    }
  }

  // MARK: - 실패·적용 안 됨

  /// 적용 실패·적용 안 됨 줄.
  static func testConditionsMessage(_ message: AndroidTestConditionsMessage) -> String {
    switch message {
    case let .failed(_, error):
      self.testConditionsFailure(error)
    case .notApplied(.appearance):
      String(localized: "외관이 바뀌지 않았습니다. 이 기기의 Android 버전이 지원하지 않을 수 있습니다.", bundle: .module)
    case .notApplied(.location):
      String(localized: "에뮬레이터가 위치를 받지 않았습니다.", bundle: .module)
    }
  }

  /// 읽기·적용 실패 본문. 꺼짐은 이 시트의 문구, 그 밖은 기존 Android 기기 오류 문구 (없는 기기 문구는 iOS 와 같은 공통 문구다).
  static func testConditionsFailure(_ error: AndroidEmulatorError) -> String {
    if error == .deviceNotBooted {
      return String(localized: "기기가 꺼져 있습니다. 기기를 켠 뒤 다시 시도하세요.", bundle: .module)
    }
    // 취소·레이아웃 에러는 이 시트의 명령이 던지지 않는다. 혹시 오면 adb 문구로 보인다.
    return self.message(for: error) ?? self.message(for: .adbUnavailable) ?? ""
  }
}
