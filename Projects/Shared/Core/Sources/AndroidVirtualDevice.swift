/// Android 기기(AVD) 하나. `~/.android/avd` 의 `<이름>.ini` 와 그 기기 폴더에서 읽는다 (Android Studio 가 만든 것 포함).
public struct AndroidVirtualDevice: Identifiable, Hashable, Sendable {
  /// AVD 이름 (`<이름>.ini` 의 이름). emulator `-avd` 인자이자 폴더 이름.
  public struct ID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }
  }

  /// 기기 상태. 잠금 파일과 adb 로 정한다 (`AndroidDeviceJudge.state`).
  public enum State: Hashable, Sendable {
    case shutdown, booting, booted
  }

  /// 쓸 수 없는 이유. emulator 의 실패 문구는 원인과 맞지 않아(실측) 켜기 전에 파일로 정한다.
  public enum UnavailableReason: Hashable, Sendable {
    /// emulator 가 죽는 이름 (공백·한글 등, 실측 SIGSEGV).
    case unsupportedName
    /// `path` 의 폴더가 없다.
    case folderMissing
    /// config.ini 없음·읽지 못함·형식 틀림.
    case configUnreadable
    /// 이미지 경로 키 없음·형식 틀림(nil) 또는 지금 SDK 에 없음.
    case systemImageMissing(AndroidSystemImageRef?)
    /// 이 Mac 에서 못 도는 abi (Apple 실리콘의 x86_64 등).
    case unsupportedABI(String)
  }

  public enum Availability: Hashable, Sendable {
    case available
    case unavailable(UnavailableReason)
  }

  /// 짧은 변이 600dp 이상이면 tablet.
  public enum FormFactor: Hashable, Sendable {
    case phone, tablet

    public static let tabletMinimumDP = 600

    /// 픽셀 크기와 dpi 로 정한다 (dp = 픽셀 × 160 / dpi).
    public init(width: Int, height: Int, density: Int) {
      let shortSide = min(width, height)
      let isTablet = density > 0 && shortSide * 160 >= Self.tabletMinimumDP * density
      self = isTablet ? .tablet : .phone
    }
  }

  public let id: ID
  /// 표시 이름 (`avd.ini.displayname`, 없으면 AVD 이름). 번역하지 않는다.
  public let displayName: String
  /// 이미지 참조 (이미지 경로를 읽었을 때). 화면의 "API 37.0 · Google APIs".
  public let systemImage: AndroidSystemImageRef?
  public let formFactor: FormFactor?
  public let state: State
  public let availability: Availability

  public init(
    id: ID,
    displayName: String,
    systemImage: AndroidSystemImageRef?,
    formFactor: FormFactor?,
    state: State,
    availability: Availability
  ) {
    self.id = id
    self.displayName = displayName
    self.systemImage = systemImage
    self.formFactor = formFactor
    self.state = state
    self.availability = availability
  }
}

/// `system-images/android-<api>/<tag>/<abi>/` 하나.
public struct AndroidSystemImageRef: Hashable, Sendable {
  /// "android-37.0".
  public let apiFolder: String
  /// "google_apis".
  public let tag: String
  /// "arm64-v8a".
  public let abi: String

  /// 세 구성 요소가 `AndroidPackagePath` 규칙(비지 않음, `.`·`..` 아님, `/`·NUL 없음)을 지키고
  /// `apiFolder` 가 `android-` 로 시작하고 그 뒤가 비지 않을 때만 만들어진다.
  public init?(apiFolder: String, tag: String, abi: String) {
    guard
      apiFolder.hasPrefix(Self.apiPrefix),
      apiFolder.count > Self.apiPrefix.count,
      let path = AndroidPackagePath([apiFolder, tag, abi].joined(separator: ";")),
      path.components.count == 3
    else {
      return nil
    }
    self.apiFolder = apiFolder
    self.tag = tag
    self.abi = abi
  }

  /// "37.0" (`android-` 뒤).
  public var apiLabel: String {
    String(self.apiFolder.dropFirst(Self.apiPrefix.count))
  }

  /// `image.sysdir.1` 값 (`system-images/android-37.0/google_apis/arm64-v8a/`, SDK 루트 기준, 끝 `/`).
  public var sysdirValue: String {
    "\(Self.rootFolder)/\(self.apiFolder)/\(self.tag)/\(self.abi)/"
  }

  /// `image.sysdir.1` 값을 읽는다. 앞뒤 `/` 하나씩 허용, 구성 요소 4개(`system-images` + 3).
  public static func parse(sysdir: String) -> AndroidSystemImageRef? {
    var value = Substring(sysdir)
    if value.hasPrefix("/") {
      value = value.dropFirst()
    }
    if value.hasSuffix("/") {
      value = value.dropLast()
    }
    let components = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard components.count == 4, components[0] == self.rootFolder else {
      return nil
    }
    return AndroidSystemImageRef(apiFolder: components[1], tag: components[2], abi: components[3])
  }

  private static let apiPrefix = "android-"
  private static let rootFolder = "system-images"
}
