import Foundation

/// Android 앱 패키지 이름. 1~255 자, `.` 로 나눈 구성 요소 2개 이상, 구성 요소마다 `[A-Za-z][A-Za-z0-9_]*`.
/// 이 문자만 허용하므로 adb 원격 셸 인자로 인용 없이 넣어도 안전하다 (Impl 은 패키지 자리는 인용하지 않고, component·링크 자리만 인용한다).
/// 규칙은 Android `PackageParser.validateName(requireSeparator: true)` 와 같고, 255 자 상한은 앱이 정한 안전 상한이다.
public struct AndroidPackageName: Hashable, Sendable, Comparable {
  public static let maxLength = 255

  public let rawValue: String

  public init?(_ raw: String) {
    let scalars = raw.unicodeScalars
    guard (1 ... Self.maxLength).contains(scalars.count) else {
      return nil
    }
    let components = raw.split(separator: ".", omittingEmptySubsequences: false)
    guard components.count >= 2, components.allSatisfy(Self.isValidComponent) else {
      return nil
    }
    self.rawValue = raw
  }

  public static func < (lhs: AndroidPackageName, rhs: AndroidPackageName) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  /// 비지 않고, 첫 글자가 ASCII 영문자, 나머지가 ASCII 영숫자·`_`.
  private static func isValidComponent(_ component: Substring) -> Bool {
    guard let first = component.unicodeScalars.first, isLetter(first) else {
      return false
    }
    return component.unicodeScalars.dropFirst()
      .allSatisfy { Self.isLetter($0) || ("0" ... "9").contains($0) || $0 == "_" }
  }

  private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
    ("a" ... "z").contains(scalar) || ("A" ... "Z").contains(scalar)
  }
}

/// manifest 의 minSdkVersion.
public enum AndroidMinSDK: Hashable, Sendable {
  /// 정수 값. `uses-sdk` 나 속성이 없으면 Android 기본값 1.
  case level(Int)
  /// 리소스 참조(`@integer/…`)·미리보기 코드명 문자열 등 앱이 풀지 않는 값. 판정을 건너뛰고 기기에 맡긴다.
  case unresolved
}

/// 검사한 apk. AndroidPackage Client Impl 이 만든다. 설치 가능 판정은 `installProblem(on:)`.
public struct AndroidPackageInfo: Hashable, Sendable {
  /// 링크를 푼 실제 경로 (확장자 .apk, 대소문자 무시). 검사한 이 경로를 adb install 에도 넘긴다.
  public let location: URL
  public let packageName: AndroidPackageName
  public let minSDK: AndroidMinSDK
  /// `lib/<abi>/` 아래 파일이 있는 abi 이름. 비면 기기 ABI 와 무관(네이티브 코드 없음).
  public let nativeABIs: Set<String>

  /// 기본값을 두지 않는다: 값을 다시 만드는 경로가 필드를 조용히 잃지 않게 컴파일러가 잡는다.
  public init(location: URL, packageName: AndroidPackageName, minSDK: AndroidMinSDK, nativeABIs: Set<String>) {
    self.location = location
    self.packageName = packageName
    self.minSDK = minSDK
    self.nativeABIs = nativeABIs
  }
}

/// 켜진 기기의 API 수준과 지원 ABI (`getprop`). AndroidEmulator Client 가 돌려준다.
public struct AndroidDeviceTraits: Hashable, Sendable {
  public let apiLevel: Int
  /// `ro.product.cpu.abilist` 순서 그대로 ("arm64-v8a").
  public let abis: [String]

  public init(apiLevel: Int, abis: [String]) {
    self.apiLevel = apiLevel
    self.abis = abis
  }
}

/// apk 를 그 기기에 설치할 수 없는 이유 (Core 판정).
public enum AndroidInstallProblem: Hashable, Sendable {
  /// apk 의 네이티브 코드 ABI 가 기기 ABI 와 하나도 겹치지 않는다. app = apk 의 abi (정렬), device = 기기 abilist (순서 그대로).
  case noMatchingABI(app: [String], device: [String])
  /// 기기 API < minSdk.
  case requiresNewerAPI(required: Int, device: Int)
}

public extension AndroidPackageInfo {
  /// 첫 문제 하나: ABI → API 순서 (iOS 의 아키텍처 → OS 순서와 같다). 없으면 nil. `nativeABIs` 가 비면 ABI 는 보지 않고,
  /// `.unresolved` 면 API 는 보지 않는다. 기기 API 와 minSdk 가 같으면 통과.
  func installProblem(on traits: AndroidDeviceTraits) -> AndroidInstallProblem? {
    if !self.nativeABIs.isEmpty, self.nativeABIs.isDisjoint(with: traits.abis) {
      return .noMatchingABI(app: self.nativeABIs.sorted(), device: traits.abis)
    }
    if case let .level(required) = self.minSDK, traits.apiLevel < required {
      return .requiresNewerAPI(required: required, device: traits.apiLevel)
    }
    return nil
  }
}

/// 행에서 앱 설치·실행·링크 열기를 막는 이유.
public enum AndroidAppActionBlockReason: Hashable, Sendable {
  /// 쓸 수 없는 기기.
  case unavailable
  /// 꺼짐·켜는 중 (켜진 기기만 된다).
  case notBooted
}

/// 그 기기에서 지금 앱 설치·실행·링크 열기를 할 수 있는지.
public enum AndroidAppActionAvailability: Hashable, Sendable {
  case allowed
  case blocked(AndroidAppActionBlockReason)
}

public extension AndroidVirtualDevice {
  /// 쓸 수 없으면 blocked(.unavailable) (상태보다 먼저), `.booted` 면 allowed, 그 밖은 blocked(.notBooted).
  /// Model 가드와 View(버튼 비활성·드롭 거절·이유)가 함께 쓴다. 설치·실행·링크 열기 모두 이 규칙이다 (꺼진 기기를 켜고 설치하지 않는다).
  var appActionAvailability: AndroidAppActionAvailability {
    if self.availability != .available {
      return .blocked(.unavailable)
    }
    return self.state == .booted ? .allowed : .blocked(.notBooted)
  }
}
