import AndroidEmulatorInterface
import Core
import Foundation

/// 테스트 조건 시트의 앱 단위 구역(앱 고르기·권한·푸시 알림 불가 안내) 문구. "(공통)" 문구는 iOS 기기 목록(Launcher)의
/// `LauncherText+AppConditions.swift` 와 같은 키·값이다 (`LauncherTextSyncTests` 가 확인한다).
extension AndroidDevicesText {
  // MARK: - 앱

  /// (공통) 앱 구역 제목이자 앱 고르기 Picker 이름.
  static var appSection: String {
    String(localized: "앱", bundle: .module)
  }

  /// (공통) 앱을 고르지 않은 Picker 값.
  static var noAppSelected: String {
    String(localized: "앱을 고르세요", bundle: .module)
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

  /// (공통) 앱을 고르지 않았을 때 권한 구역의 한 줄.
  static var selectAppFirst: String {
    String(localized: "위에서 앱을 고르세요.", bundle: .module)
  }

  // MARK: - 권한

  /// (공통)
  static var privacySection: String {
    String(localized: "권한", bundle: .module)
  }

  /// 런타임 권한 이름: 알려진 권한은 한국어 이름, 나머지는 원래 이름의 마지막 조각 (`android.permission.BLUETOOTH_CONNECT` →
  /// `BLUETOOTH_CONNECT`).
  static func permissionName(_ permission: AndroidRuntimePermission) -> String {
    guard let known = AndroidKnownPermission(permission) else {
      return permission.rawValue.split(separator: ".").last.map(String.init) ?? permission.rawValue
    }
    return self.knownPermissionName(known)
  }

  /// 알려진 권한 이름. 카메라·마이크·미디어·저장소 권한은 `mediaPermissionName(_:)` 이 고른다.
  static func knownPermissionName(_ permission: AndroidKnownPermission) -> String {
    switch permission {
    case .fineLocation: String(localized: "정확한 위치", bundle: .module)
    case .coarseLocation: String(localized: "대략적인 위치", bundle: .module)
    case .backgroundLocation: String(localized: "백그라운드 위치", bundle: .module)
    case .camera, .recordAudio, .mediaImages, .mediaVideo, .mediaVisualUserSelected, .mediaAudio, .readExternalStorage,
         .writeExternalStorage:
      self.mediaPermissionName(permission)
    case .readContacts: String(localized: "연락처 읽기", bundle: .module)
    case .writeContacts: String(localized: "연락처 쓰기", bundle: .module)
    case .readCalendar: String(localized: "캘린더 읽기", bundle: .module)
    case .writeCalendar: String(localized: "캘린더 쓰기", bundle: .module)
    case .postNotifications: String(localized: "알림", bundle: .module)
    }
  }

  /// 카메라·마이크·미디어·저장소 권한 이름 (`knownPermissionName(_:)` 이 부른다. 그 밖의 권한은 그쪽 이름으로 돌려보낸다).
  private static func mediaPermissionName(_ permission: AndroidKnownPermission) -> String {
    switch permission {
    case .camera: String(localized: "카메라", bundle: .module)
    case .recordAudio: String(localized: "마이크", bundle: .module)
    case .mediaImages: String(localized: "사진", bundle: .module)
    case .mediaVideo: String(localized: "동영상", bundle: .module)
    case .mediaVisualUserSelected: String(localized: "선택한 사진·동영상", bundle: .module)
    case .mediaAudio: String(localized: "음악·오디오", bundle: .module)
    case .readExternalStorage: String(localized: "저장소 읽기", bundle: .module)
    case .writeExternalStorage: String(localized: "저장소 쓰기", bundle: .module)
    case .fineLocation, .coarseLocation, .backgroundLocation, .readContacts, .writeContacts, .readCalendar,
         .writeCalendar,
         .postNotifications:
      self.knownPermissionName(permission)
    }
  }

  /// 허용된 권한 행 아래 안내 (끄면 = 거부).
  static var permissionTerminationNote: String {
    String(localized: "끄면 실행 중인 앱이 종료됩니다(로그도 끝납니다).", bundle: .module)
  }

  static var permissionDenyNote: String {
    String(localized: "끄면 앱이 다시 물을 수 있는 상태가 됩니다.", bundle: .module)
  }

  static var noRuntimePermissions: String {
    String(localized: "이 앱은 바꿀 수 있는 권한을 요청하지 않습니다.", bundle: .module)
  }

  static var permissionsAppNotInstalled: String {
    String(localized: "앱이 기기에 없습니다. 앱 목록 다시 읽기를 누르세요.", bundle: .module)
  }

  // MARK: - 푸시 알림

  /// (공통)
  static var pushSection: String {
    String(localized: "푸시 알림", bundle: .module)
  }

  static var pushUnsupportedNote: String {
    String(
      localized: "Android 앱 푸시(FCM)는 Google 서버를 거쳐야 해서 SimLauncher 가 에뮬레이터에 보낼 수 없습니다.",
      bundle: .module
    )
  }

  // MARK: - 적용 안 됨

  /// 권한을 쓴 뒤 다시 읽은 값이 요청과 다르거나 그 권한이 목록에 없다.
  static func permissionNotApplied(_ permission: AndroidRuntimePermission) -> String {
    String(
      localized: "\(self.permissionName(permission)) 권한이 바뀌지 않았습니다. 바꿀 수 없는 권한일 수 있습니다.",
      bundle: .module
    )
  }

  /// 권한을 쓰는 동안 앱이 기기에서 없어졌다. 패키지 이름은 번역하지 않는 값이다.
  static func appNotInstalled(_ package: AndroidPackageName) -> String {
    String(localized: "\(package.rawValue) 앱이 기기에 없습니다. 앱 목록 다시 읽기를 누르세요.", bundle: .module)
  }
}
