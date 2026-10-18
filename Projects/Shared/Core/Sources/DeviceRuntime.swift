/// 시뮬레이터 런타임이 대상으로 하는 플랫폼. 화면에는 `.iOS` 런타임의 기기만 보인다.
public enum DevicePlatform: Hashable, Sendable {
  case iOS, watchOS, tvOS, visionOS, other

  /// `simctl list -j` 의 런타임 `platform` 값으로 만든다.
  /// "iOS"·"watchOS" 는 실제 출력에서 확인했고, "tvOS"·"xrOS"·"visionOS" 는 미확인이다. 그 밖의 값은 `.other`.
  public init(simctlPlatform raw: String) {
    switch raw {
    case "iOS": self = .iOS
    case "watchOS": self = .watchOS
    case "tvOS": self = .tvOS
    case "xrOS", "visionOS": self = .visionOS
    default: self = .other
    }
  }
}

/// 런타임 OS 버전. "27.0"·"26.0.1" 처럼 점으로 나뉜 숫자 1~3 개.
public struct OSVersion: Hashable, Sendable, Comparable {
  public let major: Int
  public let minor: Int
  public let patch: Int

  public init(major: Int, minor: Int = 0, patch: Int = 0) {
    self.major = major
    self.minor = minor
    self.patch = patch
  }

  /// 점으로 나뉜 음이 아닌 정수 1~3 개가 아니면 nil.
  public init?(_ string: String) {
    let parts = string.split(separator: ".", omittingEmptySubsequences: false)
    guard (1 ... 3).contains(parts.count) else { return nil }
    var numbers: [Int] = []
    for part in parts {
      guard !part.isEmpty, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber), let number = Int(part) else {
        return nil
      }
      numbers.append(number)
    }
    self.init(
      major: numbers[0],
      minor: numbers.count > 1 ? numbers[1] : 0,
      patch: numbers.count > 2 ? numbers[2] : 0
    )
  }

  public static func < (lhs: OSVersion, rhs: OSVersion) -> Bool {
    (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
  }
}

/// 시뮬레이터 런타임(기기가 돌리는 OS 한 벌).
public struct DeviceRuntime: Identifiable, Hashable, Sendable {
  /// simctl 런타임 식별자 (예: "com.apple.CoreSimulator.SimRuntime.iOS-27-0").
  public struct ID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }
  }

  public let id: ID
  public let platform: DevicePlatform
  public let version: OSVersion
  /// 화면에 그대로 보이는 이름 (예: "iOS 27.0").
  public let name: String
  /// 이 Mac 에서 지금 쓸 수 있는 런타임인지.
  public let isAvailable: Bool

  public init(id: ID, platform: DevicePlatform, version: OSVersion, name: String, isAvailable: Bool) {
    self.id = id
    self.platform = platform
    self.version = version
    self.name = name
    self.isAvailable = isAvailable
  }
}
