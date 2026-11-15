import AndroidEmulatorInterface
import Core
import Foundation

/// 이름을 한국어로 보이고 목록 앞에 두는 런타임 권한 (선언 순서가 표시 순서다). 나머지 권한은 원래 이름으로 뒤에 둔다.
enum AndroidKnownPermission: String, CaseIterable {
  case fineLocation = "android.permission.ACCESS_FINE_LOCATION"
  case coarseLocation = "android.permission.ACCESS_COARSE_LOCATION"
  case backgroundLocation = "android.permission.ACCESS_BACKGROUND_LOCATION"
  case camera = "android.permission.CAMERA"
  case recordAudio = "android.permission.RECORD_AUDIO"
  case mediaImages = "android.permission.READ_MEDIA_IMAGES"
  case mediaVideo = "android.permission.READ_MEDIA_VIDEO"
  case mediaVisualUserSelected = "android.permission.READ_MEDIA_VISUAL_USER_SELECTED"
  case mediaAudio = "android.permission.READ_MEDIA_AUDIO"
  case readExternalStorage = "android.permission.READ_EXTERNAL_STORAGE"
  case writeExternalStorage = "android.permission.WRITE_EXTERNAL_STORAGE"
  case readContacts = "android.permission.READ_CONTACTS"
  case writeContacts = "android.permission.WRITE_CONTACTS"
  case readCalendar = "android.permission.READ_CALENDAR"
  case writeCalendar = "android.permission.WRITE_CALENDAR"
  case postNotifications = "android.permission.POST_NOTIFICATIONS"

  init?(_ permission: AndroidRuntimePermission) {
    self.init(rawValue: permission.rawValue)
  }

  /// 표시 순서 (선언 순서).
  var order: Int {
    Self.allCases.firstIndex(of: self) ?? Self.allCases.count
  }
}

/// Android 테스트 조건 시트의 앱 단위 구역 초안: 켜진 기기의 사용자 설치 패키지 목록(`installedPackages`, "앱 실행…" 과 같은 목록),
/// 고른 패키지, 그 앱의 런타임 권한 읽기 상태. `AndroidTestConditionsDraft.app` 으로 갖고, 바꾸는 메서드는 Model 만
/// `AndroidTestConditionsDraft.updateApp(_:)` 으로 부른다.
public struct AndroidTestConditionsAppDraft: Hashable, Sendable {
  /// 설치된 패키지 목록.
  public enum PackageList: Hashable, Sendable {
    case loading
    case loaded([AndroidPackageName])
    case failed(AndroidEmulatorError)
  }

  /// 고른 앱의 런타임 권한.
  public enum PermissionsState: Hashable, Sendable {
    /// 앱을 고르지 않았다.
    case idle
    case loading
    /// `runtime permissions:` 블록 순서 그대로 (표시 순서는 `sortedPermissions`). 비면 바꿀 수 있는 권한을 요청하지 않는 앱.
    case loaded([AndroidPermissionGrant])
    /// 앱이 기기에 없다 (목록을 읽은 뒤 지워졌다).
    case appNotInstalled
    case failed(AndroidEmulatorError)
  }

  public private(set) var packages: PackageList = .loading
  /// 패키지 목록 읽기 요청 번호. 같은 시트에서 다시 읽으면 늘어, 앞 읽기의 늦은 결과를 버린다.
  public private(set) var packagesRequest = 0
  /// 고른 패키지. 늘 `.loaded` 목록에 있는 값이다.
  public private(set) var selectedPackage: AndroidPackageName?
  public private(set) var permissions: PermissionsState = .idle
  /// 권한 읽기 요청 번호. 다시 읽거나 다른 앱을 고르면 늘어, 앞 읽기의 늦은 결과를 버린다.
  public private(set) var permissionsRequest = 0

  init() {}

  // MARK: - 계산

  /// 표시 순서의 권한: 알려진 권한(`AndroidKnownPermission` 순서) 먼저, 나머지는 원래 이름 순. 읽지 않았으면 빈 목록.
  public var sortedPermissions: [AndroidPermissionGrant] {
    guard case let .loaded(grants) = self.permissions else { return [] }
    return grants.sorted { lhs, rhs in
      switch (AndroidKnownPermission(lhs.permission), AndroidKnownPermission(rhs.permission)) {
      case let (left?, right?): left.order < right.order
      case (.some, .none): true
      case (.none, .some): false
      case (.none, .none): lhs.permission < rhs.permission
      }
    }
  }

  /// 읽은 권한 중 이것의 지금 값 (읽지 않았거나 목록에 없으면 nil).
  func grant(of permission: AndroidRuntimePermission) -> AndroidPermissionGrant? {
    guard case let .loaded(grants) = self.permissions else { return nil }
    return grants.first { $0.permission == permission }
  }

  // MARK: - 바꾸기 (Model 만 부른다)

  mutating func packagesStarted() {
    self.packages = .loading
    self.packagesRequest += 1
  }

  /// 읽은 목록을 보인다. 선택 규칙은 iOS(`TestConditionsAppDraft.appsLoaded`)와 같다: 지금 고른 패키지가 새 목록에 있으면 그대로, 없으면
  /// 이 기기에서 마지막으로 고른 패키지(`remembered`)가 목록에 있으면 그것, 아니면 패키지가 하나일 때만 그것, 아니면 고르지 않음.
  /// 고르지 않으면 권한은 `.idle`.
  mutating func packagesLoaded(_ packages: [AndroidPackageName], remembered: AndroidPackageName?) {
    self.packages = .loaded(packages)
    if let current = self.selectedPackage, packages.contains(current) {
      return
    }
    if let remembered, packages.contains(remembered) {
      self.selectedPackage = remembered
    } else if packages.count == 1 {
      self.selectedPackage = packages.first
    } else {
      self.selectedPackage = nil
      self.permissions = .idle
    }
  }

  /// 목록을 읽지 못했다. 선택과 권한도 지운다.
  mutating func packagesFailed(_ error: AndroidEmulatorError) {
    self.packages = .failed(error)
    self.selectedPackage = nil
    self.permissions = .idle
  }

  /// 패키지를 고른다. nil 이거나 `.loaded` 목록에 있는 값만 받는다 (받았으면 true). nil 이면 권한은 `.idle`.
  mutating func packageSelected(_ package: AndroidPackageName?) -> Bool {
    if let package {
      guard case let .loaded(packages) = self.packages, packages.contains(package) else { return false }
    }
    self.selectedPackage = package
    if package == nil {
      self.permissions = .idle
      // 그 전 앱의 늦은 읽기 결과를 버린다.
      self.permissionsRequest += 1
    }
    return true
  }

  /// 권한 읽기를 시작한다 (요청 번호를 올린다).
  mutating func permissionsStarted() {
    self.permissions = .loading
    self.permissionsRequest += 1
  }

  mutating func permissionsChanged(_ state: PermissionsState) {
    self.permissions = state
  }
}
