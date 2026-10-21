import Core
import DevEnvironmentInterface
import SimulatorInterface

/// 기본 iOS 런타임 확인 결과. Xcode 가 준비됨일 때만 확인한다 (`simctl runtime list` 와 SDK 파일만 읽고 네트워크를 쓰지 않는다).
public enum SetupRuntimeState: Hashable, Sendable {
  /// Xcode 가 준비되지 않았거나 아직 확인 전.
  case notChecked
  /// 기본 iOS(이 Xcode 의 iOS Simulator SDK)와 그 설치 여부.
  case checked(DefaultIOSRuntime, DefaultIOSRuntimeStatus)
  /// 이 Xcode 의 기본 iOS 버전을 읽지 못했다 (`defaultIOSRuntime()` 이 nil). 런타임 이미지는 읽지 않았다.
  case defaultRuntimeUnknown
  /// 런타임 이미지 목록을 읽지 못했다.
  case failed(SimulatorError)

  /// 기본 iOS 이미지가 Ready 다.
  public var isInstalled: Bool {
    guard case .checked(_, .installed) = self else { return false }
    return true
  }
}

/// 진행 중인 설치. 화면은 `progress.phase` 로 단계를 고른다.
public struct SetupRuntimeInstall: Hashable, Sendable {
  /// 마지막으로 받은 진행. 시작 값은 `.preparing`.
  public private(set) var progress: RuntimeInstallProgress = .preparing
  /// 60초 동안 진행 알림이 없었다 (준비·내려받기 단계에서만). 실패가 아니고, 다음 진행 알림에 지워진다.
  public private(set) var isStalled = false
  /// 취소를 눌러 멈추는 중 (xcodebuild 가 끝나기를 기다린다).
  public private(set) var isCancelling = false
  /// 사용자가 앱 종료를 확정해 설치가 끝나면 앱을 끝낸다.
  public private(set) var endsWithTermination = false

  /// 취소를 누를 수 있다: 설치 단계(installing)가 아니고, 멈추는 중이 아니다.
  public var canCancel: Bool {
    self.progress.phase != .installing && !self.isCancelling
  }

  /// 새 진행을 받았다. 무진행 안내를 지운다.
  mutating func progressed(_ update: RuntimeInstallProgress) {
    self.progress = update
    self.isStalled = false
  }

  /// 진행 알림 없이 무진행 시간이 지났다.
  mutating func stalled() {
    self.isStalled = true
  }

  /// 취소를 눌렀다. 멈추는 동안은 무진행 안내를 보이지 않는다.
  mutating func cancelling() {
    self.isCancelling = true
    self.isStalled = false
  }

  /// 앱 종료를 확정했다.
  mutating func terminating() {
    self.endsWithTermination = true
  }
}

/// 끝난 설치의 결과.
public enum SetupInstallResult: Hashable, Sendable {
  case finished(RuntimeInstallOutcome)
  /// `.cancelled` 포함.
  case failed(RuntimeInstallError)
}

/// App 이 종료 요청을 받았을 때 할 일.
public enum SetupTerminationAction: Hashable, Sendable {
  /// 설치 중이 아니다: 바로 종료.
  case terminateNow
  /// 준비·내려받기 중: 확인을 받은 뒤 취소하고 끝나기를 기다린다.
  case confirmThenCancel
  /// 설치 단계(취소 끔)이거나 이미 멈추는 중·종료 대기 중: 묻지 않고 끝나기를 기다린다.
  case waitForInstall
}
