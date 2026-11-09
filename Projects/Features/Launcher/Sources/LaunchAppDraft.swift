import Core

/// 앱 실행 시트 초안. 기기는 "앱 실행…" 을 누른 시점의 값이고, 목록은 그 기기에서 읽은 사용자 설치 앱이다.
/// 꺼진 기기면 시트가 먼저 열려 켜는 동안 `.booting` 을 보이고, 켜지면 `.loading` 을 거쳐 목록을 보인다.
/// 준비(켜기)·목록 읽기를 다시 할 때마다 Model 이 새 번호(`request`)를 붙여, 시트를 닫았다 다시 열거나 다시 시도한 뒤
/// 늦게 온 앞 결과를 버린다. 바꾸는 메서드는 Model 만 부른다 (View 는 Model 의 `launchAppDraft` 를 읽기만 한다).
public struct LaunchAppDraft: Hashable, Sendable {
  /// 설치한 앱 목록을 불러온 상태.
  public enum Apps: Hashable, Sendable {
    /// 꺼진 기기를 켜는 중 (켜지면 목록을 읽는다).
    case booting
    case loading
    /// 표시 이름 → 번들 ID 순. 비면 직접 설치한 앱이 없다.
    case loaded([InstalledApp])
    /// 켜기(`.boot`)나 목록 읽기·준비 판정(`.list`)이 실패했다.
    case failed(InstalledAppLaunchFailure, stage: LaunchAppFailureStage)
  }

  public let deviceID: VirtualDevice.ID
  /// 시트 제목과 실패 알림에 보일 기기 (누른 시점의 이름·런타임 이름).
  public let device: LauncherNotice.Device
  /// 지금 기다리는 준비·목록 읽기의 번호.
  public private(set) var request: Int
  public private(set) var apps: Apps
  public private(set) var selection: AppBundleID?

  init(deviceID: VirtualDevice.ID, device: LauncherNotice.Device, request: Int, booting: Bool) {
    self.deviceID = deviceID
    self.device = device
    self.request = request
    self.apps = booting ? .booting : .loading
  }

  /// 실행을 누를 수 있는지: 목록을 불러왔고 고른 앱이 그 목록에 있다.
  public var canSubmit: Bool {
    self.selectedApp != nil
  }

  /// 불러온 목록에서 고른 앱. 목록이 없거나 고른 앱이 없으면 nil.
  public var selectedApp: InstalledApp? {
    guard case let .loaded(apps) = self.apps, let selection = self.selection else { return nil }
    return apps.first { $0.bundleID == selection }
  }

  mutating func selectionChanged(_ bundleID: AppBundleID?) {
    self.selection = bundleID
  }

  /// 새 번호로 준비부터 다시 시작한다 (실패 뒤 "다시 시도"). 켜야 하면 `.booting`, 아니면 `.loading`. 고른 앱은 유지한다.
  mutating func reloadStarted(request: Int, booting: Bool) {
    self.request = request
    self.apps = booting ? .booting : .loading
  }

  /// 켜기가 끝나 목록 읽기를 시작한다. 번호가 같고 켜는 중일 때만 `.loading` 으로 바꾼다.
  mutating func loadingStarted(request: Int) {
    guard request == self.request, self.apps == .booting else { return }
    self.apps = .loading
  }

  /// 번호가 지금 기다리는 것과 같을 때만 반영한다. 목록에 하나뿐이면 그것을 고르고, 고른 앱이 목록에 없으면 선택을 지운다.
  mutating func appsLoaded(_ result: Result<[InstalledApp], LaunchAppPreparationFailure>, request: Int) {
    guard request == self.request else { return }
    switch result {
    case let .success(apps):
      self.apps = .loaded(apps)
      if let selection = self.selection, !apps.contains(where: { $0.bundleID == selection }) {
        self.selection = nil
      }
      if self.selection == nil, apps.count == 1 {
        self.selection = apps.first?.bundleID
      }
    case let .failure(failure):
      self.apps = .failed(failure.failure, stage: failure.stage)
    }
  }
}

/// 앱 실행 시트의 실패가 난 단계. 시트가 실패 본문 위에 보일 한 줄 제목을 고른다.
public enum LaunchAppFailureStage: Hashable, Sendable {
  /// 꺼진 기기를 켜지 못했다.
  case boot
  /// 목록을 읽지 못했다 (준비 판정 실패 포함: 기기가 없어짐·켜는 중).
  case list
}

/// 앱 실행 시트의 준비(켜기)나 목록 읽기 실패: 원인과 단계.
public struct LaunchAppPreparationFailure: Error, Hashable, Sendable {
  public let failure: InstalledAppLaunchFailure
  public let stage: LaunchAppFailureStage

  public init(_ failure: InstalledAppLaunchFailure, stage: LaunchAppFailureStage) {
    self.failure = failure
    self.stage = stage
  }
}
