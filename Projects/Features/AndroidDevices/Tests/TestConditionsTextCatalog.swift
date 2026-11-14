import AndroidEmulatorInterface
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 테스트 조건 문구(`AndroidDevicesText+TestConditions.swift`)의 String Catalog 키. `DownloadTextCatalog` 와 같은 방식으로
/// `AndroidDevicesResourcesTests` 는 이 모듈의 컴파일된 표로 모든 키를, `LauncherTextSyncTests` 는 Launcher 원본 표로 공유 키를 본다.
enum TestConditionsTextCatalog {
  typealias Check = DownloadTextCatalog.Check

  static let sentAt = Date(timeIntervalSince1970: 1_800_000_000)

  /// iOS 기기 목록(Launcher)의 `LauncherText+TestConditions.swift` 와 같은 키·값으로 둔 문구 ("(공통)").
  static func sharedChecks(_ table: [String: String]) -> [Check] {
    var pairs: [(String, String)] = [
      ("테스트 조건…", AndroidDevicesText.testConditionsButton),
      ("켜진 기기에서만 바꿀 수 있습니다.", AndroidDevicesText.testConditionsBootedOnlyHelp),
      ("바꾼 조건은 기기에 바로 적용되고, 시트를 닫거나 SimLauncher 를 꺼도 기기에 남습니다.", AndroidDevicesText.testConditionsSheetNote),
      ("화면", AndroidDevicesText.displaySection),
      ("외관", AndroidDevicesText.appearanceLabel),
      ("라이트", AndroidDevicesText.appearanceName(.light)),
      ("다크", AndroidDevicesText.appearanceName(.dark)),
      ("지금 값을 읽는 중…", AndroidDevicesText.readingConditions),
      ("지금 값을 읽지 못했습니다.", AndroidDevicesText.conditionsReadFailed),
      ("다시 읽기", AndroidDevicesText.rereadButton),
      ("적용하는 중…", AndroidDevicesText.applyingCondition),
      ("위치", AndroidDevicesText.locationSection),
      ("위도, 경도", AndroidDevicesText.coordinateField),
      ("예: 37.5665, 126.9780", AndroidDevicesText.coordinatePlaceholder),
      ("자주 쓰는 위치", AndroidDevicesText.locationPresetsMenu),
      ("이 위치로 설정", AndroidDevicesText.setPointButton),
      (
        "기기에서 지금 위치를 읽을 수 없어 SimLauncher 가 보낸 기록만 보입니다. 다른 도구로 바꾸면 달라질 수 있습니다.",
        AndroidDevicesText.sentLocationNote
      ),
      ("기기를 끄거나 초기화해도 이 기록은 남습니다.", AndroidDevicesText.sentLocationKeptNote),
      ("위도, 경도를 숫자로 넣으세요. 소수점은 마침표(.)입니다.", AndroidDevicesText.coordinateProblem(.format)),
      ("위도는 -90 에서 90 사이여야 합니다.", AndroidDevicesText.coordinateProblem(.latitudeOutOfRange)),
      ("경도는 -180 에서 180 사이여야 합니다.", AndroidDevicesText.coordinateProblem(.longitudeOutOfRange)),
      (
        "기기가 꺼져 있습니다. 기기를 켠 뒤 다시 시도하세요.",
        AndroidDevicesText.testConditionsFailure(.deviceNotBooted)
      ),
      ("기기를 찾지 못했습니다. 목록을 새로 고친 뒤 다시 시도하세요.", AndroidDevicesText.testConditionsFailure(.deviceNotFound)),
    ]
    let presets = ["서울", "도쿄", "쿠퍼티노", "뉴욕", "런던", "시드니"]
    pairs += zip(presets, LocationPreset.allCases.map(AndroidDevicesText.presetName)).map { ($0, $1) }
    return pairs.map { DownloadTextCatalog.check(table, $0.0, $0.1) } + self.sharedFormatChecks(table)
  }

  /// 보간이 든 공유 키 (표의 값에 인자를 넣은 문구가 코드 결과와 같아야 한다).
  private static func sharedFormatChecks(_ table: [String: String]) -> [Check] {
    let point = GeoCoordinate(latitude: -33.8688, longitude: 151.2093)!
    let pointText = AndroidDevicesText.coordinateText(point)
    return [
      DownloadTextCatalog.check(
        table,
        "%@ 테스트 조건",
        AndroidDevicesText.testConditionsSheetTitle(for: AndroidDeviceLabel(name: "Pixel Tablet", apiLabel: "37.0")),
        "Pixel Tablet"
      ),
      DownloadTextCatalog.check(table, "%@, %@", pointText, "-33.8688", "151.2093"),
      DownloadTextCatalog.check(
        table,
        "SimLauncher 가 마지막으로 보낸 위치 (%@): %@",
        AndroidDevicesText.sentLocationLine(AndroidSentLocation(coordinate: point, sentAt: self.sentAt)),
        self.sentAt.formatted(date: .omitted, time: .standard),
        pointText
      ),
    ]
  }

  /// Android 문장 (iOS 는 글씨 크기·경로·시나리오가 있어 문장이 다르다).
  static func androidChecks(_ table: [String: String]) -> [Check] {
    let pairs: [(String, String)] = [
      ("외관·위치 같은 테스트 조건을 바꿉니다.", AndroidDevicesText.testConditionsHelp),
      ("지금은 자동·예약 모드입니다. 라이트·다크를 고르면 바뀝니다.", AndroidDevicesText.nightModeOtherNote),
      (
        "Android 기기는 경로·시나리오를 지원하지 않습니다. 에뮬레이터 창의 ⋯ > Location 에서 경로를 재생할 수 있습니다.",
        AndroidDevicesText.routeUnsupportedNote
      ),
      ("기기의 위치 서비스가 꺼져 있어 앱이 위치를 받지 못합니다. 기기 설정 > 위치에서 켜세요.", AndroidDevicesText.locationServiceOffNote),
      (
        "외관이 바뀌지 않았습니다. 이 기기의 Android 버전이 지원하지 않을 수 있습니다.",
        AndroidDevicesText.testConditionsMessage(.notApplied(.appearance))
      ),
      ("에뮬레이터가 위치를 받지 않았습니다.", AndroidDevicesText.testConditionsMessage(.notApplied(.location))),
    ]
    return pairs.map { DownloadTextCatalog.check(table, $0.0, $0.1) }
  }
}

/// 테스트 조건 문구 함수가 각 케이스에 돌려주는 값.
struct AndroidTestConditionsTextTests {
  @Test("적용 실패 본문: 꺼짐은 시트 문구, 그 밖은 기존 Android 기기 오류 문구")
  func failureMessages() {
    #expect(
      AndroidDevicesText.testConditionsMessage(.failed(.appearance, .deviceNotBooted))
        == "기기가 꺼져 있습니다. 기기를 켠 뒤 다시 시도하세요."
    )
    for error in [AndroidEmulatorError.adbUnavailable, .sdkUnavailable, .deviceNotFound] {
      #expect(AndroidDevicesText.testConditionsFailure(error) == AndroidDevicesText.message(for: error))
    }
    // 이 시트의 명령이 던지지 않는 취소도 빈 글자가 아니다.
    #expect(AndroidDevicesText.testConditionsFailure(.cancelled) == AndroidDevicesText.message(for: .adbUnavailable))
  }

  @Test("공유 문구 32개와 Android 문구 6개")
  func checkCounts() {
    #expect(Set(TestConditionsTextCatalog.sharedChecks([:]).map(\.key)).count == 32)
    #expect(Set(TestConditionsTextCatalog.androidChecks([:]).map(\.key)).count == 6)
  }
}
