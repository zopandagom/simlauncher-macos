import Core
import DevEnvironmentInterface

/// 개발 환경 확인 결과.
public enum SetupCheckState: Hashable, Sendable {
  /// 아직 한 번도 판정하지 못했다 (첫 확인 중이거나 시작 전).
  case checking
  /// 마지막 확인 결과.
  case checked(DevEnvironmentStatus)
  /// 마지막 확인이 실패했다 (Impl 은 `.checkFailed` 만 던지지만 타입의 모든 케이스를 다룬다).
  case failed(DevEnvironmentError)
}

/// 띄울 열기 실패 알림.
public enum SetupNotice: Hashable, Sendable {
  case openAppStoreFailed(DevEnvironmentError)
  case openXcodeFailed(DevEnvironmentError)
}

/// 준비 단계 하나와 그 진행. 화면은 세 단계를 늘 같은 순서로 보이고 지금 할 단계만 강조한다.
public struct SetupStep: Hashable, Sendable, Identifiable {
  public enum Kind: Hashable, Sendable, CaseIterable {
    case installXcode, acceptLicense, firstLaunch
  }

  public enum Progress: Hashable, Sendable {
    case done, current, pending
  }

  public let kind: Kind
  public let progress: Progress

  public var id: Kind {
    self.kind
  }

  public init(kind: Kind, progress: Progress) {
    self.kind = kind
    self.progress = progress
  }

  /// 상태별 세 단계 (설치 → 라이선스 → 첫 실행 준비 순서). 지금 할 단계 앞은 done, 뒤는 pending 이고,
  /// 준비됨이면 모두 done 이다.
  public static func steps(for status: DevEnvironmentStatus) -> [SetupStep] {
    let currentIndex: Int? = switch status {
    case .xcodeNotInstalled, .commandLineToolsOnly:
      0
    case .licenseNotAccepted:
      1
    case .firstLaunchRequired:
      2
    case .ready:
      nil
    }
    return Kind.allCases.enumerated().map { index, kind in
      guard let currentIndex else {
        return SetupStep(kind: kind, progress: .done)
      }
      let progress: Progress = index < currentIndex ? .done : index == currentIndex ? .current : .pending
      return SetupStep(kind: kind, progress: progress)
    }
  }
}
