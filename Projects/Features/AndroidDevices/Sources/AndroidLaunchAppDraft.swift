import AndroidEmulatorInterface
import Core

/// 앱 실행 시트 초안. 기기는 "앱 실행…" 을 누른 시점의 값이고, 목록은 그 기기에서 읽은 사용자 설치 앱(패키지 이름)이다.
/// 목록을 다시 불러올 때마다 Model 이 새 번호(`request`)를 붙여, 시트를 닫았다 다시 열거나 다시 시도한 뒤 늦게 온 앞 결과를 버린다.
/// 바꾸는 메서드는 Model 만 부른다 (View 는 Model 의 `launchAppDraft` 를 읽기만 한다).
public struct AndroidLaunchAppDraft: Hashable, Sendable {
  /// 설치한 앱 목록을 불러온 상태.
  public enum Packages: Hashable, Sendable {
    case loading
    /// 이름순. 비면 직접 설치한 앱이 없다.
    case loaded([AndroidPackageName])
    case failed(AndroidEmulatorError)
  }

  public let deviceID: AndroidVirtualDevice.ID
  /// 시트 제목과 실패 알림에 보일 기기 (누른 시점의 이름·API).
  public let device: AndroidDeviceLabel
  /// 지금 기다리는 목록 불러오기의 번호.
  public private(set) var request: Int
  public private(set) var packages: Packages = .loading
  public private(set) var selection: AndroidPackageName?

  init(deviceID: AndroidVirtualDevice.ID, device: AndroidDeviceLabel, request: Int) {
    self.deviceID = deviceID
    self.device = device
    self.request = request
  }

  /// 실행을 누를 수 있는지: 목록을 불러왔고 고른 앱이 그 목록에 있다.
  public var canSubmit: Bool {
    guard case let .loaded(packages) = self.packages, let selection = self.selection else { return false }
    return packages.contains(selection)
  }

  mutating func selectionChanged(_ package: AndroidPackageName?) {
    self.selection = package
  }

  /// 새 번호로 다시 불러오기를 시작한다 (실패 뒤 "다시 시도"). 고른 앱은 유지한다.
  mutating func reloadStarted(request: Int) {
    self.request = request
    self.packages = .loading
  }

  /// 번호가 지금 기다리는 것과 같을 때만 반영한다. 목록에 하나뿐이면 그것을 고르고, 고른 앱이 목록에 없으면 선택을 지운다.
  mutating func packagesLoaded(_ result: Result<[AndroidPackageName], AndroidEmulatorError>, request: Int) {
    guard request == self.request else { return }
    switch result {
    case let .success(packages):
      self.packages = .loaded(packages)
      if let selection = self.selection, !packages.contains(selection) {
        self.selection = nil
      }
      if self.selection == nil, packages.count == 1 {
        self.selection = packages.first
      }
    case let .failure(error):
      self.packages = .failed(error)
    }
  }
}
