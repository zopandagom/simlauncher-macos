/// 고른 Xcode 의 기본 iOS 런타임 = 그 Xcode 의 iOS Simulator SDK 버전 (DevEnvironment Client 의 런타임 설치가 받는 대상).
public struct DefaultIOSRuntime: Hashable, Sendable {
  /// SDK `SDKSettings.plist` 의 `Version` (예: 27.1).
  public let version: OSVersion
  /// SDK `SystemVersion.plist` 의 `ProductBuildVersion` (예: "24A94232"). 읽지 못하면 nil.
  public let build: String?

  public init(version: OSVersion, build: String?) {
    self.version = version
    self.build = build
  }
}

/// 기본 iOS 런타임이 이 Mac 에 있는지. 화면 문구·다음 할 일은 Feature 가 정한다.
public enum DefaultIOSRuntimeStatus: Hashable, Sendable {
  /// 같은 major.minor 의 iOS 이미지가 Ready 다.
  case installed(RuntimeImage)
  /// 받은 뒤 확인·마운트 중.
  case preparing(RuntimeImage)
  /// 있지만 쓸 수 없다.
  case unusable(RuntimeImage)
  /// 후보 이미지가 없다 (삭제 중·알 수 없는 상태만 있는 경우 포함).
  case notInstalled

  /// 후보: `platform == .iOS` 이고 version 의 major·minor 가 같은 이미지 (patch·build 는 보지 않는다.
  /// xcodebuild 의 iOS 런타임 설치도 SDK 와 build 가 다른 같은 버전을 설치됨으로 본다).
  /// 상태 우선순위는 ready > preparing > unusable 이고, removing·unknown 은 후보에서 뺀다 (모두 빠지면 notInstalled).
  /// 같은 상태가 여럿이면 build 가 `defaultRuntime.build` 와 같은 것 → version 이 높은 것 → `id.rawValue` 순.
  public init(defaultRuntime: DefaultIOSRuntime, images: [RuntimeImage]) {
    var candidates: [RuntimeImage] = []
    for image in images where Self.isCandidate(image, for: defaultRuntime.version) {
      candidates.append(image)
    }
    let sorted: [RuntimeImage] = candidates.sorted { lhs, rhs in
      Self.precedes(lhs, rhs, defaultBuild: defaultRuntime.build)
    }
    guard let best = sorted.first else {
      self = .notInstalled
      return
    }
    switch best.state {
    case .ready: self = .installed(best)
    case .preparing: self = .preparing(best)
    case .unusable: self = .unusable(best)
    case .removing, .unknown: self = .notInstalled
    }
  }

  private static func isCandidate(_ image: RuntimeImage, for version: OSVersion) -> Bool {
    guard image.platform == .iOS, self.rank(image.state) != nil else { return false }
    return image.version.major == version.major && image.version.minor == version.minor
  }

  /// 작을수록 앞. 후보가 아닌 상태는 nil.
  private static func rank(_ state: RuntimeImage.State) -> Int? {
    switch state {
    case .ready: 0
    case .preparing: 1
    case .unusable: 2
    case .removing, .unknown: nil
    }
  }

  private static func precedes(_ lhs: RuntimeImage, _ rhs: RuntimeImage, defaultBuild: String?) -> Bool {
    let lhsRank = Self.rank(lhs.state) ?? Int.max
    let rhsRank = Self.rank(rhs.state) ?? Int.max
    if lhsRank != rhsRank {
      return lhsRank < rhsRank
    }
    let lhsMatches = defaultBuild != nil && lhs.build == defaultBuild
    let rhsMatches = defaultBuild != nil && rhs.build == defaultBuild
    if lhsMatches != rhsMatches {
      return lhsMatches
    }
    if lhs.version != rhs.version {
      return lhs.version > rhs.version
    }
    return lhs.id.rawValue < rhs.id.rawValue
  }
}
