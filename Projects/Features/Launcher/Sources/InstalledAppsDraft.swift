import Core
import SimulatorInterface

/// 설치된 앱 시트의 마지막 동작 결과 줄. 다음 동작(확인한 삭제)을 시작하면 지운다. 앱 이름은 동작을 시작한 때의 값이다.
public enum InstalledAppsMessage: Hashable, Sendable {
  case removed(appName: String)
  case failed(InstalledAppsDraft.Action, SimulatorError)
}

/// iOS 기기 행 "설치된 앱…" 시트 초안: 켜진 기기의 사용자 설치 앱 목록(`installedApps`, "앱 실행…" 과 같은 목록), 고른 앱,
/// 확인을 기다리는 동작과 진행 중인 동작, 마지막 결과 줄. 열 때마다 Model 이 새 번호(`session`)를 붙여 닫았다 다시 연 뒤 늦게 온 앞
/// 결과를 버린다. 쓰기(삭제)와 목록 읽기는 겹치지 않는다: 읽는 동안 쓰기를 확인할 수 없고(`canRequestAction`·`canConfirm(_:)`),
/// 쓰는 동안 다시 읽기·고르기·닫기를 받지 않는다(`canRefresh`·`canClose`, Model 의 `loadApps` 가드).
/// 바꾸는 메서드는 Model 만 부른다 (View 는 Model 의 `draft` 를 읽기만 한다).
public struct InstalledAppsDraft: Hashable, Sendable {
  /// 설치된 앱 목록.
  public enum AppList: Hashable, Sendable {
    /// 첫 읽기 (보일 목록이 아직 없다).
    case loading
    case loaded([InstalledApp])
    /// 마지막으로 읽은 목록과 선택을 그대로 보이며 다시 읽는 중.
    case reloading([InstalledApp])
    case failed(SimulatorError)
  }

  /// 확인을 받아 기기를 바꾸는 동작. 앱 이름·번들 ID 는 고른 때의 값이다.
  public enum Action: Hashable, Sendable {
    case remove(InstalledApp)

    /// 동작 대상 앱.
    public var app: InstalledApp {
      switch self {
      case let .remove(app): app
      }
    }
  }

  public let deviceID: VirtualDevice.ID
  /// 시트 제목·확인 대화상자에 보일 기기 (누른 시점의 이름·런타임 이름).
  public let device: LauncherNotice.Device
  /// 이 시트를 연 번호.
  public let session: Int
  public private(set) var apps: AppList = .loading
  /// 앱 목록 읽기 요청 번호. 같은 시트에서 다시 읽으면 늘어, 앞 읽기의 늦은 결과를 버린다.
  public private(set) var appsRequest = 0
  /// 고른 앱. 늘 `loadedApps` 목록에 있는 값이다.
  public private(set) var selection: AppBundleID?
  /// 확인 대화상자에 보일 동작 (확인을 기다린다).
  public private(set) var pendingAction: Action?
  /// 확인해 기기에서 진행 중인 동작.
  public private(set) var runningAction: Action?
  /// 마지막 동작의 결과 줄.
  public private(set) var message: InstalledAppsMessage?

  init(deviceID: VirtualDevice.ID, device: LauncherNotice.Device, session: Int) {
    self.deviceID = deviceID
    self.device = device
    self.session = session
  }

  // MARK: - 계산

  /// 보이는 앱 목록: 읽었거나(`.loaded`) 다시 읽는 중(`.reloading`, 마지막 목록)이면 그 목록, 아니면 nil.
  public var loadedApps: [InstalledApp]? {
    switch self.apps {
    case let .loaded(apps), let .reloading(apps): apps
    case .loading, .failed: nil
    }
  }

  /// 앱 목록을 읽는 중인가 (첫 읽기·다시 읽기).
  public var isReadingApps: Bool {
    switch self.apps {
    case .loading, .reloading: true
    case .loaded, .failed: false
    }
  }

  /// 고른 앱 (보이는 목록에 있는 값).
  public var selectedApp: InstalledApp? {
    guard let apps = self.loadedApps, let id = self.selection else { return nil }
    return apps.first { $0.bundleID == id }
  }

  /// 기기에서 동작이 진행 중이다 (고르기·다시 읽기·닫기를 받지 않는다).
  public var isBusy: Bool {
    self.runningAction != nil
  }

  /// "삭제…" 를 누를 수 있다: 고른 앱이 있고, 목록을 읽는 중이 아니며, 확인 대기·진행 중인 동작이 없다.
  public var canRequestAction: Bool {
    self.selectedApp != nil && !self.isReadingApps && self.pendingAction == nil && self.runningAction == nil
  }

  /// "앱 목록 다시 읽기" 를 누를 수 있다: 읽는 중이 아니고 확인 대기·진행 중인 동작이 없다.
  public var canRefresh: Bool {
    !self.isReadingApps && self.runningAction == nil && self.pendingAction == nil
  }

  /// 시트를 닫을 수 있다 (진행 중인 동작이 없다). 닫기 버튼·Esc·시스템 닫기가 이것을 따른다.
  public var canClose: Bool {
    self.runningAction == nil
  }

  /// 확인 대화상자의 "삭제" 로 이 동작을 받아들인다: 확인을 기다리는 동작이 이것이거나 대화상자가 이미 닫혔고(SwiftUI 는 버튼 동작
  /// 뒤 곧바로 대화상자를 닫는다), 진행 중인 동작이 없고, 목록을 읽는 중이 아니며, 대상 앱이 보이는 목록에 있다 (확인을 기다리는 동안
  /// 목록 읽기가 시작됐거나 대상이 목록에서 빠졌으면 받지 않는다).
  public func canConfirm(_ action: Action) -> Bool {
    guard self.pendingAction == nil || self.pendingAction == action,
          self.runningAction == nil,
          !self.isReadingApps,
          let apps = self.loadedApps
    else { return false }
    return apps.contains { $0.bundleID == action.app.bundleID }
  }

  // MARK: - 바꾸기 (Model 만 부른다)

  /// 앱 목록 읽기를 시작한다 (요청 번호를 올린다). 보일 목록이 있으면 그 목록과 선택을 그대로 두고 `.reloading` 으로, 없으면
  /// (첫 읽기·실패 뒤) `.loading` 으로.
  mutating func appsStarted() {
    if let apps = self.loadedApps {
      self.apps = .reloading(apps)
    } else {
      self.apps = .loading
    }
    self.appsRequest += 1
  }

  /// 읽은 목록을 보인다. 선택: 지금 고른 앱이 새 목록에 있으면 그대로, 없으면 앱이 하나일 때만 그 앱, 아니면 고르지 않음.
  mutating func appsLoaded(_ apps: [InstalledApp]) {
    self.apps = .loaded(apps)
    let ids = apps.map(\.bundleID)
    if let current = self.selection, ids.contains(current) {
      return
    }
    self.selection = ids.count == 1 ? ids.first : nil
  }

  /// 목록을 읽지 못했다 (다시 읽기였어도). 선택도 지운다 (실패한 기기의 마지막 목록은 믿지 않는다).
  mutating func appsFailed(_ error: SimulatorError) {
    self.apps = .failed(error)
    self.selection = nil
  }

  /// 앱을 고른다. 진행 중인 동작이 있으면 받지 않고, nil 이거나 보이는 목록에 있는 값만 받는다.
  mutating func selectionChanged(_ id: AppBundleID?) {
    guard self.runningAction == nil else { return }
    if let id {
      guard let apps = self.loadedApps, apps.contains(where: { $0.bundleID == id }) else { return }
    }
    self.selection = id
  }

  /// 확인 대화상자를 띄운다.
  mutating func actionRequested(_ action: Action) {
    self.pendingAction = action
  }

  /// 확인 대화상자를 닫는다 (취소·받아들이지 않은 확인).
  mutating func actionCancelled() {
    self.pendingAction = nil
  }

  /// 확인한 동작을 시작한다. 마지막 결과 줄을 지운다.
  mutating func actionStarted(_ action: Action) {
    self.runningAction = action
    self.pendingAction = nil
    self.message = nil
  }

  /// 앱을 지웠다: 보이는 목록에서 그 앱을 빼고(`.loaded`), 고른 앱이 그 앱이면 선택을 지우고, 결과 줄을 보인다.
  mutating func appRemoved(_ app: InstalledApp) {
    self.runningAction = nil
    let remaining = (self.loadedApps ?? []).filter { $0.bundleID != app.bundleID }
    self.apps = .loaded(remaining)
    if self.selection == app.bundleID {
      self.selection = nil
    }
    self.message = .removed(appName: app.displayName)
  }

  /// 동작이 실패했다. 목록·선택은 그대로 둔다 (Model 이 다시 읽어 실제 상태를 맞춘다).
  mutating func actionFailed(_ action: Action, _ error: SimulatorError) {
    self.runningAction = nil
    self.message = .failed(action, error)
  }
}
