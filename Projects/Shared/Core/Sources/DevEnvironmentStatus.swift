/// 쓸 Xcode 의 준비 상태. 화면 문구·다음 할 일은 Feature 가 케이스별로 정한다.
public enum DevEnvironmentStatus: Hashable, Sendable {
  /// 쓸 수 있는 Xcode 가 없고, xcode-select 도 Command Line Tools 를 가리키지 않는다 (아무 도구도 없음, 깨진 경로).
  case xcodeNotInstalled
  /// 쓸 수 있는 Xcode 가 없고, xcode-select 가 Command Line Tools 를 가리킨다.
  case commandLineToolsOnly
  /// 이 Xcode 버전의 라이선스에 동의하지 않았다.
  case licenseNotAccepted(XcodeInstallation)
  /// 라이선스는 동의했지만 첫 실행 준비(추가 구성요소 설치)가 남았다.
  case firstLaunchRequired(XcodeInstallation)
  case ready(XcodeInstallation)

  /// 판정 순서: Xcode 없음(CLT 선택 여부로 둘 중 하나) → 라이선스 → 첫 실행 준비 → 준비됨.
  /// xcode 가 nil 이면 `checks` 는 보지 않는다 (Impl 은 `.notRun` 을 넘긴다).
  public init(xcode: XcodeInstallation?, commandLineToolsSelected: Bool, checks: XcodeSetupChecks) {
    guard let xcode else {
      self = commandLineToolsSelected ? .commandLineToolsOnly : .xcodeNotInstalled
      return
    }
    if !checks.licenseAccepted {
      self = .licenseNotAccepted(xcode)
    } else if !checks.firstLaunchComplete {
      self = .firstLaunchRequired(xcode)
    } else {
      self = .ready(xcode)
    }
  }

  /// 상태가 가리키는 Xcode (없음·CLT 면 nil). 화면의 "쓰는 Xcode" 표시에 쓴다.
  public var xcode: XcodeInstallation? {
    switch self {
    case .xcodeNotInstalled, .commandLineToolsOnly:
      nil
    case let .licenseNotAccepted(xcode), let .firstLaunchRequired(xcode), let .ready(xcode):
      xcode
    }
  }

  public var isReady: Bool {
    if case .ready = self {
      return true
    }
    return false
  }
}

/// 고른 Xcode 에서 실행한 확인 결과 (Impl 이 종료 코드를 해석해 만든다).
public struct XcodeSetupChecks: Hashable, Sendable {
  public let licenseAccepted: Bool
  public let firstLaunchComplete: Bool

  public init(licenseAccepted: Bool, firstLaunchComplete: Bool) {
    self.licenseAccepted = licenseAccepted
    self.firstLaunchComplete = firstLaunchComplete
  }

  /// Xcode 가 없어 확인하지 않음 (두 값 false). xcode nil 과만 함께 쓴다.
  public static let notRun = XcodeSetupChecks(licenseAccepted: false, firstLaunchComplete: false)
}
