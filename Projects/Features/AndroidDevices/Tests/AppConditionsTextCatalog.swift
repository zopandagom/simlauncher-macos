import AndroidEmulatorInterface
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 테스트 조건 앱 단위 구역 문구(`AndroidDevicesText+AppConditions.swift`)의 String Catalog 키. `DownloadTextCatalog` 와 같은 방식으로
/// `AndroidDevicesResourcesTests` 는 이 모듈의 컴파일된 표로 모든 키를, `LauncherTextSyncTests` 는 Launcher 원본 표로 공유 키를 본다.
enum AppConditionsTextCatalog {
  typealias Check = DownloadTextCatalog.Check

  static let package = AndroidPackageName("com.example.sample")!
  static let camera = AndroidRuntimePermission("android.permission.CAMERA")!

  /// iOS 기기 목록(Launcher)의 `LauncherText+AppConditions.swift` 와 같은 키·값으로 둔 문구 ("(공통)"). 카메라·마이크·사진은 iOS 권한
  /// 이름과 키·값이 같아 함께 맞춘다.
  static func sharedChecks(_ table: [String: String]) -> [Check] {
    let pairs: [(String, String)] = [
      ("앱", AndroidDevicesText.appSection),
      ("앱을 고르세요", AndroidDevicesText.noAppSelected),
      ("앱 목록을 읽는 중…", AndroidDevicesText.readingApps),
      ("앱 목록을 읽지 못했습니다.", AndroidDevicesText.appsReadFailed),
      ("이 기기에 설치한 앱이 없습니다. 앱을 설치한 뒤 앱 목록 다시 읽기를 누르세요.", AndroidDevicesText.noInstalledAppsForConditions),
      ("앱 목록 다시 읽기", AndroidDevicesText.refreshAppsButton),
      ("시트를 연 뒤 설치한 앱은 앱 목록 다시 읽기로 보입니다.", AndroidDevicesText.appsRefreshNote),
      ("위에서 앱을 고르세요.", AndroidDevicesText.selectAppFirst),
      ("권한", AndroidDevicesText.privacySection),
      ("푸시 알림", AndroidDevicesText.pushSection),
      ("카메라", AndroidDevicesText.knownPermissionName(.camera)),
      ("마이크", AndroidDevicesText.knownPermissionName(.recordAudio)),
      ("사진", AndroidDevicesText.knownPermissionName(.mediaImages)),
    ]
    return pairs.map { DownloadTextCatalog.check(table, $0.0, $0.1) }
  }

  /// Android 문장 (iOS 에 같은 키가 없다).
  static func androidChecks(_ table: [String: String]) -> [Check] {
    var pairs: [(String, String)] = [
      ("끄면 실행 중인 앱이 종료됩니다(로그도 끝납니다).", AndroidDevicesText.permissionTerminationNote),
      ("끄면 앱이 다시 물을 수 있는 상태가 됩니다.", AndroidDevicesText.permissionDenyNote),
      ("이 앱은 바꿀 수 있는 권한을 요청하지 않습니다.", AndroidDevicesText.noRuntimePermissions),
      ("앱이 기기에 없습니다. 앱 목록 다시 읽기를 누르세요.", AndroidDevicesText.permissionsAppNotInstalled),
      (
        "Android 앱 푸시(FCM)는 Google 서버를 거쳐야 해서 SimLauncher 가 에뮬레이터에 보낼 수 없습니다.",
        AndroidDevicesText.pushUnsupportedNote
      ),
    ]
    let names: [(String, AndroidKnownPermission)] = [
      ("정확한 위치", .fineLocation), ("대략적인 위치", .coarseLocation), ("백그라운드 위치", .backgroundLocation),
      ("동영상", .mediaVideo), ("선택한 사진·동영상", .mediaVisualUserSelected), ("음악·오디오", .mediaAudio),
      ("저장소 읽기", .readExternalStorage), ("저장소 쓰기", .writeExternalStorage), ("연락처 읽기", .readContacts),
      ("연락처 쓰기", .writeContacts), ("캘린더 읽기", .readCalendar), ("캘린더 쓰기", .writeCalendar),
      ("알림", .postNotifications),
    ]
    pairs += names.map { ($0.0, AndroidDevicesText.knownPermissionName($0.1)) }
    return pairs.map { DownloadTextCatalog.check(table, $0.0, $0.1) } + [
      DownloadTextCatalog.check(
        table,
        "%@ 권한이 바뀌지 않았습니다. 바꿀 수 없는 권한일 수 있습니다.",
        AndroidDevicesText.testConditionsMessage(.permissionNotApplied(self.camera, granted: true)),
        "카메라"
      ),
      DownloadTextCatalog.check(
        table,
        "%@ 앱이 기기에 없습니다. 앱 목록 다시 읽기를 누르세요.",
        AndroidDevicesText.testConditionsMessage(.appNotInstalled(self.package)),
        "com.example.sample"
      ),
    ]
  }
}

/// 앱 단위 구역 문구 함수가 각 케이스에 돌려주는 값.
struct AndroidAppConditionsTextTests {
  @Test("공유 문구 13개와 Android 문구 20개")
  func checkCounts() {
    #expect(Set(AppConditionsTextCatalog.sharedChecks([:]).map(\.key)).count == 13)
    #expect(Set(AppConditionsTextCatalog.androidChecks([:]).map(\.key)).count == 20)
  }

  @Test("알려진 권한 16개는 모두 한국어 이름이고, 모르는 권한은 원래 이름의 마지막 조각이다")
  func permissionNames() throws {
    #expect(AndroidKnownPermission.allCases.count == 16)
    for known in AndroidKnownPermission.allCases {
      let permission = try #require(AndroidRuntimePermission(known.rawValue))
      #expect(AndroidDevicesText.permissionName(permission) == AndroidDevicesText.knownPermissionName(known))
    }
    let bluetooth = try #require(AndroidRuntimePermission("android.permission.BLUETOOTH_CONNECT"))
    #expect(AndroidDevicesText.permissionName(bluetooth) == "BLUETOOTH_CONNECT")
    let custom = try #require(AndroidRuntimePermission("com.example.app.permission.C2D"))
    #expect(AndroidDevicesText.permissionName(custom) == "C2D")
  }

  @Test("적용 안 됨은 요청 값과 관계없이 같은 문구이고, 권한 실패 본문은 기존 시트 실패 문구와 같다")
  func messages() {
    let camera = AppConditionsTextCatalog.camera
    #expect(
      AndroidDevicesText.testConditionsMessage(.permissionNotApplied(camera, granted: false))
        == "카메라 권한이 바뀌지 않았습니다. 바꿀 수 없는 권한일 수 있습니다."
    )
    #expect(
      AndroidDevicesText.testConditionsMessage(.notApplied(.permission(camera)))
        == AndroidDevicesText.testConditionsMessage(.permissionNotApplied(camera, granted: true))
    )
    #expect(
      AndroidDevicesText.testConditionsMessage(.failed(.permission(camera), .deviceNotBooted))
        == "기기가 꺼져 있습니다. 기기를 켠 뒤 다시 시도하세요."
    )
  }
}
