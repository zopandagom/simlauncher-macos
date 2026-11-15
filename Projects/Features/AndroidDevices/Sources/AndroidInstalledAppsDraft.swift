import AndroidEmulatorInterface
import Core

/// Android 설치된 앱 시트의 마지막 동작 결과 줄. 다음 동작(확인한 삭제)을 시작하면 지운다.
public enum AndroidInstalledAppsMessage: Hashable, Sendable {
  case removed(AndroidPackageName)
  case failed(AndroidInstalledAppsDraft.Action, AndroidEmulatorError)
}

/// Android 기기 행 "설치된 앱…" 시트 초안: 켜진 에뮬레이터의 사용자 설치 패키지 목록(`installedPackages`, "앱 실행…" 과 같은 목록),
/// 고른 패키지, 확인을 기다리는 동작과 진행 중인 동작, 마지막 결과 줄. iOS `InstalledAppsDraft` 와 같은 모양이다 (앱 이름 대신
/// 패키지 이름). 열 때마다 Model 이 새 번호(`session`)를 붙여 닫았다 다시 연 뒤 늦게 온 앞 결과를 버린다. 쓰기(삭제)와 목록 읽기는
/// 겹치지 않는다: 읽는 동안 쓰기를 확인할 수 없고(`canRequestAction`·`canConfirm(_:)`), 쓰는 동안 다시 읽기·고르기·닫기를 받지
/// 않는다(`canRefresh`·`canClose`, Model 의 `loadPackages` 가드). 바꾸는 메서드는 Model 만 부른다.
public struct AndroidInstalledAppsDraft: Hashable, Sendable {
  /// 설치된 패키지 목록.
  public enum PackageList: Hashable, Sendable {
    /// 첫 읽기 (보일 목록이 아직 없다).
    case loading
    case loaded([AndroidPackageName])
    /// 마지막으로 읽은 목록과 선택을 그대로 보이며 다시 읽는 중.
    case reloading([AndroidPackageName])
    case failed(AndroidEmulatorError)
  }

  /// 확인을 받아 기기를 바꾸는 동작.
  public enum Action: Hashable, Sendable {
    case remove(AndroidPackageName)

    /// 동작 대상 패키지.
    public var package: AndroidPackageName {
      switch self {
      case let .remove(package): package
      }
    }
  }

  public let deviceID: AndroidVirtualDevice.ID
  /// 시트 제목·확인 대화상자에 보일 기기 (누른 시점의 이름·API).
  public let device: AndroidDeviceLabel
  /// 이 시트를 연 번호.
  public let session: Int
  public private(set) var packages: PackageList = .loading
  /// 패키지 목록 읽기 요청 번호. 같은 시트에서 다시 읽으면 늘어, 앞 읽기의 늦은 결과를 버린다.
  public private(set) var packagesRequest = 0
  /// 고른 패키지. 늘 `loadedPackages` 목록에 있는 값이다.
  public private(set) var selection: AndroidPackageName?
  /// 확인 대화상자에 보일 동작 (확인을 기다린다).
  public private(set) var pendingAction: Action?
  /// 확인해 기기에서 진행 중인 동작.
  public private(set) var runningAction: Action?
  /// 마지막 동작의 결과 줄.
  public private(set) var message: AndroidInstalledAppsMessage?

  init(deviceID: AndroidVirtualDevice.ID, device: AndroidDeviceLabel, session: Int) {
    self.deviceID = deviceID
    self.device = device
    self.session = session
  }

  // MARK: - 계산

  /// 보이는 패키지 목록: 읽었거나(`.loaded`) 다시 읽는 중(`.reloading`, 마지막 목록)이면 그 목록, 아니면 nil.
  public var loadedPackages: [AndroidPackageName]? {
    switch self.packages {
    case let .loaded(packages), let .reloading(packages): packages
    case .loading, .failed: nil
    }
  }

  /// 패키지 목록을 읽는 중인가 (첫 읽기·다시 읽기).
  public var isReadingPackages: Bool {
    switch self.packages {
    case .loading, .reloading: true
    case .loaded, .failed: false
    }
  }

  /// 고른 패키지 (보이는 목록에 있는 값).
  public var selectedPackage: AndroidPackageName? {
    guard let packages = self.loadedPackages, let selection = self.selection, packages.contains(selection) else {
      return nil
    }
    return selection
  }

  /// 기기에서 동작이 진행 중이다 (고르기·다시 읽기·닫기를 받지 않는다).
  public var isBusy: Bool {
    self.runningAction != nil
  }

  /// "삭제…" 를 누를 수 있다: 고른 패키지가 있고, 목록을 읽는 중이 아니며, 확인 대기·진행 중인 동작이 없다.
  public var canRequestAction: Bool {
    self.selectedPackage != nil && !self.isReadingPackages && self.pendingAction == nil && self.runningAction == nil
  }

  /// "앱 목록 다시 읽기" 를 누를 수 있다: 읽는 중이 아니고 확인 대기·진행 중인 동작이 없다.
  public var canRefresh: Bool {
    !self.isReadingPackages && self.runningAction == nil && self.pendingAction == nil
  }

  /// 시트를 닫을 수 있다 (진행 중인 동작이 없다). 닫기 버튼·Esc·시스템 닫기가 이것을 따른다.
  public var canClose: Bool {
    self.runningAction == nil
  }

  /// 확인 대화상자의 "삭제" 로 이 동작을 받아들인다: 확인을 기다리는 동작이 이것이거나 대화상자가 이미 닫혔고(SwiftUI 는 버튼 동작
  /// 뒤 곧바로 대화상자를 닫는다), 진행 중인 동작이 없고, 목록을 읽는 중이 아니며, 대상 패키지가 보이는 목록에 있다.
  public func canConfirm(_ action: Action) -> Bool {
    guard self.pendingAction == nil || self.pendingAction == action,
          self.runningAction == nil,
          !self.isReadingPackages,
          let packages = self.loadedPackages
    else { return false }
    return packages.contains(action.package)
  }

  // MARK: - 바꾸기 (Model 만 부른다)

  /// 패키지 목록 읽기를 시작한다 (요청 번호를 올린다). 보일 목록이 있으면 그 목록과 선택을 그대로 두고 `.reloading` 으로, 없으면
  /// `.loading` 으로.
  mutating func packagesStarted() {
    if let packages = self.loadedPackages {
      self.packages = .reloading(packages)
    } else {
      self.packages = .loading
    }
    self.packagesRequest += 1
  }

  /// 읽은 목록을 보인다. 선택: 지금 고른 패키지가 새 목록에 있으면 그대로, 없으면 패키지가 하나일 때만 그것, 아니면 고르지 않음.
  mutating func packagesLoaded(_ packages: [AndroidPackageName]) {
    self.packages = .loaded(packages)
    if let current = self.selection, packages.contains(current) {
      return
    }
    self.selection = packages.count == 1 ? packages.first : nil
  }

  /// 목록을 읽지 못했다 (다시 읽기였어도). 선택도 지운다.
  mutating func packagesFailed(_ error: AndroidEmulatorError) {
    self.packages = .failed(error)
    self.selection = nil
  }

  /// 패키지를 고른다. 진행 중인 동작이 있으면 받지 않고, nil 이거나 보이는 목록에 있는 값만 받는다.
  mutating func selectionChanged(_ package: AndroidPackageName?) {
    guard self.runningAction == nil else { return }
    if let package {
      guard let packages = self.loadedPackages, packages.contains(package) else { return }
    }
    self.selection = package
  }

  mutating func actionRequested(_ action: Action) {
    self.pendingAction = action
  }

  mutating func actionCancelled() {
    self.pendingAction = nil
  }

  /// 확인한 동작을 시작한다. 마지막 결과 줄을 지운다.
  mutating func actionStarted(_ action: Action) {
    self.runningAction = action
    self.pendingAction = nil
    self.message = nil
  }

  /// 앱을 지웠다: 보이는 목록에서 그 패키지를 빼고(`.loaded`), 고른 것이 그것이면 선택을 지우고, 결과 줄을 보인다.
  mutating func packageRemoved(_ package: AndroidPackageName) {
    self.runningAction = nil
    self.packages = .loaded((self.loadedPackages ?? []).filter { $0 != package })
    if self.selection == package {
      self.selection = nil
    }
    self.message = .removed(package)
  }

  /// 동작이 실패했다. 목록·선택은 그대로 둔다 (Model 이 다시 읽어 실제 상태를 맞춘다).
  mutating func actionFailed(_ action: Action, _ error: AndroidEmulatorError) {
    self.runningAction = nil
    self.message = .failed(action, error)
  }
}
