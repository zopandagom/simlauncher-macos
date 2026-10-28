import AndroidSDKInterface
import Core
import Foundation
import WorkspaceInterface

/// SDK 상태 확인 결과. 확인은 파일만 읽어 실패가 없다 (읽지 못한 것은 쓸 수 없음으로 판정된다).
public enum AndroidSetupCheckState: Hashable, Sendable {
  /// 아직 한 번도 판정하지 못했다 (첫 확인 중이거나 시작 전).
  case checking
  /// 마지막 확인 결과.
  case checked(AndroidSDKStatus)
}

/// 설치 계획 단계. nil 이면 계획을 받거나 동의를 기다리는 중이 아니다.
public enum AndroidSetupPlanState: Hashable, Sendable {
  /// Google 저장소 XML 을 받아 계획을 만드는 중.
  case fetching
  /// 동의 기록에 없는 라이선스 원문(`toConfirm`)이 있어 동의 시트를 띄운다.
  case awaitingConsent(AndroidSDKInstallPlan, toConfirm: [AndroidLicense])
  /// 계획을 만들지 못했다. "Android 도구 설치" 가 다시 시도한다. `.cancelled` 는 여기에 오지 않는다.
  case failed(AndroidSDKPlanError)
}

/// 진행 중인 설치. 화면은 `progress` 로 패키지·단계·바이트를 그린다.
public struct AndroidSetupInstall: Hashable, Sendable {
  /// 설치하는 계획 (설치 위치·패키지).
  public let plan: AndroidSDKInstallPlan
  /// 마지막으로 받은 진행. 첫 알림 전이면 nil.
  public private(set) var progress: AndroidSDKInstallProgress?
  /// 취소를 눌렀거나 종료를 확정해 멈추는 중.
  public private(set) var isCancelling = false
  /// 사용자가 앱 종료를 확정해 설치가 끝나면 앱을 끝낸다.
  public private(set) var endsWithTermination = false

  init(plan: AndroidSDKInstallPlan) {
    self.plan = plan
  }

  /// 취소를 누를 수 있다: 마무리 단계가 아니고, 멈추는 중·종료 대기가 아니다.
  public var canCancel: Bool {
    (self.progress?.canCancel ?? true) && !self.isCancelling && !self.endsWithTermination
  }

  mutating func progressed(_ update: AndroidSDKInstallProgress) {
    self.progress = update
  }

  mutating func cancelling() {
    self.isCancelling = true
  }

  mutating func terminating() {
    self.endsWithTermination = true
  }
}

/// 끝난 설치의 결과. 새 설치를 시작하면 지운다.
public struct AndroidSetupInstallResult: Hashable, Sendable {
  public enum Kind: Hashable, Sendable {
    case finished(AndroidSDKInstallOutcome)
    /// `.cancelled` 포함.
    case failed(AndroidSDKInstallError)
  }

  public let kind: Kind
  /// 설치한 위치 (계획의 위치).
  public let root: AndroidSDKRoot
  /// 설치 뒤 확인한 SDK 위치가 `root` 와 다르다 (설치 중 설정 창에서 위치를 바꿨다). 결과 줄이 원래 위치를 알린다.
  public private(set) var locationChangedSince = false

  /// 확인한 위치로 `locationChangedSince` 를 다시 정한다.
  mutating func locationChecked(_ current: AndroidSDKRoot?) {
    self.locationChangedSince = current?.url.standardizedFileURL != self.root.url.standardizedFileURL
  }
}

/// Finder 에서 보일 대상. 경로는 Model 이 마지막 확인 결과로 정한다.
public enum AndroidSetupRevealTarget: Hashable, Sendable {
  /// SDK 위치 자체 (쓸 수 없는 위치).
  case location
  /// 쓸 수 없는 구성 요소의 맨 위 폴더.
  case component(AndroidSDKComponent)
  /// 쓸 수 없어 설치를 막는 폴더 (`AndroidSDKInstallBlocker.notWritable`).
  case blockedFolder
}

/// 띄울 알림.
public enum AndroidSetupNotice: Hashable, Sendable {
  /// Finder 에서 보이지 못했다 (폴더가 없어짐 등).
  case revealFailed(WorkspaceError)
}

/// App 이 종료 요청을 받았을 때 할 일.
public enum AndroidSetupTerminationAction: Hashable, Sendable {
  /// 설치 중이 아니다 (계획 받기·동의 대기는 메모리뿐이라 바로 종료).
  case terminateNow
  /// 받기·확인·풀기 중: 확인을 받은 뒤 취소하고 끝나기를 기다린다.
  case confirmThenCancel
  /// 마무리 단계이거나 이미 멈추는 중·종료 대기 중: 묻지 않고 끝나기를 기다린다.
  case waitForInstall
}
