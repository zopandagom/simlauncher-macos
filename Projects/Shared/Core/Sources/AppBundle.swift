import Foundation

/// 앱 번들 ID (`CFBundleIdentifier`). simctl launch 인자로 넘기므로 형식을 검사한 값만 만든다.
public struct AppBundleID: Hashable, Sendable {
  public static let maxLength = 255

  public let rawValue: String

  /// 1~255자, ASCII 영숫자·`.`·`-`·`_` 만, 첫 글자가 `-` 이 아니면 만든다. 아니면 nil.
  public init?(_ rawValue: String) {
    let scalars = rawValue.unicodeScalars
    guard
      (1 ... Self.maxLength).contains(scalars.count),
      scalars.first != "-",
      scalars.allSatisfy(Self.isAllowed)
    else { return nil }
    self.rawValue = rawValue
  }

  private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar {
    case "a" ... "z", "A" ... "Z", "0" ... "9", ".", "-", "_": true
    default: false
    }
  }
}

/// 실행 파일에 든 CPU 아키텍처 중 시뮬레이터가 실행할 수 있는 것.
public enum CPUArchitecture: Hashable, Sendable {
  case arm64, x86_64
}

/// `CFBundleSupportedPlatforms` 값.
public enum AppBundlePlatform: Hashable, Sendable {
  case iOSSimulator, iOS, other

  /// "iPhoneSimulator" → .iOSSimulator, "iPhoneOS" → .iOS, 그 밖("MacOSX" 등) → .other. 대소문자 구분.
  public init(bundlePlatform raw: String) {
    switch raw {
    case "iPhoneSimulator": self = .iOSSimulator
    case "iPhoneOS": self = .iOS
    default: self = .other
    }
  }
}

/// 로컬 .app 에서 읽은 정보. 설치 가능 판정은 `installProblem(on:hostArchitecture:)`.
public struct AppBundleInfo: Hashable, Sendable {
  public let bundleID: AppBundleID
  /// CFBundleDisplayName → CFBundleName → 파일 이름(확장자 제외) 순서. 번역하지 않는 사용자 데이터.
  /// 2-A 화면은 쓰지 않는다 (2-B·4단계 목록 표시, 알림 확장용).
  public let displayName: String
  /// CFBundleShortVersionString, 없으면 nil. 2-A 화면은 쓰지 않는다 (2-B·4단계 목록 표시용).
  public let version: String?
  /// CFBundleVersion, 없으면 nil. 2-A 화면은 쓰지 않는다 (2-B·4단계 목록 표시용).
  public let build: String?
  /// CFBundleSupportedPlatforms. 키가 없으면 nil — 플랫폼 검사를 건너뛰고 simctl 에 맡긴다
  /// (simctl 은 이 키가 아니라 실행 파일의 Mach-O 플랫폼으로 판정한다. 기기용 실행 파일이면 install 이 거절한다).
  public let platforms: Set<AppBundlePlatform>?
  /// 실행 파일 slice 중 arm64·x86_64. 그 밖의 slice(32비트 등)는 빠진다.
  public let architectures: Set<CPUArchitecture>
  /// MinimumOSVersion 을 `OSVersion(_:)` 으로 읽은 값. 없거나 읽지 못하면 nil (OS 검사를 하지 않는다).
  public let minimumOSVersion: OSVersion?
  /// 심볼릭 링크를 푼 실제 .app 경로 (파일 URL). 검사한 이 경로를 install 에도 넘겨, 검사한 것과 설치하는 것이 같게 한다.
  public let location: URL

  /// 기본값을 두지 않는다: 값을 다시 만드는 경로가 필드를 조용히 잃지 않게 컴파일러가 잡는다.
  public init(
    bundleID: AppBundleID,
    displayName: String,
    version: String?,
    build: String?,
    platforms: Set<AppBundlePlatform>?,
    architectures: Set<CPUArchitecture>,
    minimumOSVersion: OSVersion?,
    location: URL
  ) {
    self.bundleID = bundleID
    self.displayName = displayName
    self.version = version
    self.build = build
    self.platforms = platforms
    self.architectures = architectures
    self.minimumOSVersion = minimumOSVersion
    self.location = location
  }
}
