import AndroidEmulatorInterface
import Core
import Observation

/// Android 기기 행의 "앱 실행…"·"링크 열기…" 시트의 상태와 로직. 둘은 동시에 하나만 연다. 앱 실행 시트는 열 때와 "다시 시도" 때
/// 그 기기의 사용자 설치 앱 목록을 읽는다 (진행 기록 없이. 기기를 바꾸지 않는다). 확정한 앱·링크는 App 이 주입한
/// `launchRequested`·`openURLRequested` 로 기기 목록
/// 화면(`AndroidDevicesModel.launchAppRequested(_:)`·`openURLRequested(_:)`)에
/// 넘기고, 대상 재확인·진행 기록·실행은 그쪽이 한다. 목록 읽기라는 자기 비동기 흐름이 있어 `AndroidDevicesModel` 과 나눴다
/// (ARCHITECTURE §1). 나누기 전의 서로 막기는 그대로다: 시트를 열 기기는 App 이 `AndroidDevicesModel.appSheetTarget(_:for:)` 로
/// 잇는 `target` 이 정하고(목록·기기·작업 시작 가능·만들기 시트와 확인 대화상자 없음), `AndroidDevicesModel` 은 App 이 이
/// Model 의 `hasPresentedSheet` 로 잇는 클로저로 이 시트가 떠 있는지 본다.
@MainActor
@Observable
public final class AndroidAppSheetsModel {
  /// 앱 실행 시트 초안(기기에서 읽은 설치 앱 목록 포함). nil 이면 시트가 닫혀 있다.
  public private(set) var launchAppDraft: AndroidLaunchAppDraft?
  /// 링크 열기 시트 초안. nil 이면 시트가 닫혀 있다.
  public private(set) var openURLDraft: AndroidOpenURLDraft?

  @ObservationIgnored private let emulator: any AndroidEmulatorClient
  /// 그 작업의 시트를 열 수 있는 기기 (없으면 nil). App 이 `AndroidDevicesModel.appSheetTarget(_:for:)` 로 잇는다.
  @ObservationIgnored private let target: @MainActor (AndroidVirtualDevice.ID, AndroidDeviceTask)
    -> AndroidVirtualDevice?
  /// 앱 실행 시트의 "실행". App 이 `AndroidDevicesModel.launchAppRequested(_:)` 로 잇는다.
  @ObservationIgnored private let launchRequested: @MainActor (AndroidLaunchAppRequest) async -> Void
  /// 링크 열기 시트의 "열기". App 이 `AndroidDevicesModel.openURLRequested(_:)` 로 잇는다.
  @ObservationIgnored private let openURLRequested: @MainActor (AndroidOpenURLRequest) async -> Void
  /// 앱 실행 시트의 목록 불러오기 번호. 늦게 온 앞 결과를 버리는 기준이다.
  @ObservationIgnored private var nextLaunchListRequest = 0

  public init(
    emulator: any AndroidEmulatorClient,
    target: @escaping @MainActor (AndroidVirtualDevice.ID, AndroidDeviceTask) -> AndroidVirtualDevice?,
    launchRequested: @escaping @MainActor (AndroidLaunchAppRequest) async -> Void = { _ in },
    openURLRequested: @escaping @MainActor (AndroidOpenURLRequest) async -> Void = { _ in }
  ) {
    self.emulator = emulator
    self.target = target
    self.launchRequested = launchRequested
    self.openURLRequested = openURLRequested
  }

  /// 앱 실행·링크 열기 시트가 떠 있다. App 이 `AndroidDevicesModel` 의 `appSheetPresented` 로 잇는다.
  public var hasPresentedSheet: Bool {
    self.launchAppDraft != nil || self.openURLDraft != nil
  }

  // MARK: - 앱 실행

  /// 앱 실행 시트를 열고 그 기기의 사용자 설치 앱 목록을 읽는다. 읽기는 진행 기록 없이 한다 (기기를 바꾸지 않는다).
  public func launchAppTapped(_ id: AndroidVirtualDevice.ID) async {
    guard !self.hasPresentedSheet, let device = self.target(id, .launchApp) else { return }
    self.nextLaunchListRequest += 1
    let request = self.nextLaunchListRequest
    self.launchAppDraft = AndroidLaunchAppDraft(deviceID: id, device: AndroidDeviceLabel(device), request: request)
    await self.loadLaunchPackages(on: id, request: request)
  }

  /// 목록 읽기가 실패한 시트의 "다시 시도".
  public func launchAppRetryTapped() async {
    guard let draft = self.launchAppDraft, case .failed = draft.packages else { return }
    self.nextLaunchListRequest += 1
    let request = self.nextLaunchListRequest
    self.launchAppDraft?.reloadStarted(request: request)
    await self.loadLaunchPackages(on: draft.deviceID, request: request)
  }

  public func launchAppSelectionChanged(_ package: AndroidPackageName?) {
    self.launchAppDraft?.selectionChanged(package)
  }

  public func launchAppCancelTapped() {
    self.launchAppDraft = nil
  }

  public func launchAppSheetDismissed() {
    self.launchAppDraft = nil
  }

  /// 시트를 닫고 고른 앱의 실행을 요청한다. 실행이 끝날 때까지 기다린다.
  public func launchAppConfirmTapped() async {
    guard let draft = self.launchAppDraft, draft.canSubmit, let package = draft.selection else { return }
    // 첫 await 전에 닫아, 연타해도 두 번째 호출은 위에서 끝난다.
    self.launchAppDraft = nil
    await self.launchRequested(AndroidLaunchAppRequest(
      deviceID: draft.deviceID,
      device: draft.device,
      package: package
    ))
  }

  // MARK: - 링크 열기

  public func openURLTapped(_ id: AndroidVirtualDevice.ID) {
    guard !self.hasPresentedSheet, let device = self.target(id, .openURL) else { return }
    self.openURLDraft = AndroidOpenURLDraft(deviceID: id, device: AndroidDeviceLabel(device))
  }

  public func openURLTextChanged(_ text: String) {
    self.openURLDraft?.textChanged(text)
  }

  public func openURLCancelTapped() {
    self.openURLDraft = nil
  }

  public func openURLSheetDismissed() {
    self.openURLDraft = nil
  }

  /// 시트를 닫고 링크 열기를 요청한다. 열기가 끝날 때까지 기다린다.
  public func openURLConfirmTapped() async {
    // 링크에 문제가 있으면 버튼이 비활성이라 드물다. 시트와 입력은 그대로 둔다.
    guard let draft = self.openURLDraft, let link = draft.link else { return }
    self.openURLDraft = nil
    await self.openURLRequested(AndroidOpenURLRequest(deviceID: draft.deviceID, device: draft.device, link: link))
  }

  // MARK: - 내부

  /// 앱 실행 시트의 목록을 읽어, 그 초안이 아직 이 번호를 기다리면 반영한다 (닫혔거나 다시 불러왔으면 버린다).
  /// 실패도 시트에 보인다 (알림을 쌓지 않는다).
  private func loadLaunchPackages(on id: AndroidVirtualDevice.ID, request: Int) async {
    let result: Result<[AndroidPackageName], AndroidEmulatorError>
    do throws(AndroidEmulatorError) {
      result = try await .success(self.emulator.installedPackages(on: id))
    } catch {
      result = .failure(error)
    }
    self.launchAppDraft?.packagesLoaded(result, request: request)
  }
}

/// `AndroidAppSheetsModel` 이 App 을 거쳐 `AndroidDevicesModel.launchAppRequested(_:)` 에 넘기는 실행 요청.
public struct AndroidLaunchAppRequest: Hashable, Sendable {
  public let deviceID: AndroidVirtualDevice.ID
  /// 시트를 연 시점의 기기 라벨 (알림에 쓴다).
  public let device: AndroidDeviceLabel
  public let package: AndroidPackageName

  public init(deviceID: AndroidVirtualDevice.ID, device: AndroidDeviceLabel, package: AndroidPackageName) {
    self.deviceID = deviceID
    self.device = device
    self.package = package
  }
}

/// `AndroidAppSheetsModel` 이 App 을 거쳐 `AndroidDevicesModel.openURLRequested(_:)` 에 넘기는 링크 열기 요청.
public struct AndroidOpenURLRequest: Hashable, Sendable {
  public let deviceID: AndroidVirtualDevice.ID
  /// 시트를 연 시점의 기기 라벨 (알림에 쓴다).
  public let device: AndroidDeviceLabel
  public let link: DeepLink

  public init(deviceID: AndroidVirtualDevice.ID, device: AndroidDeviceLabel, link: DeepLink) {
    self.deviceID = deviceID
    self.device = device
    self.link = link
  }
}
