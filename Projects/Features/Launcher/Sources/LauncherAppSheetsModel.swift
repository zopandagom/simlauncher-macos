import Core
import Observation
import SimulatorInterface

/// iOS 기기 행의 "앱 실행…"·"링크 열기…" 시트의 상태와 로직. 둘은 동시에 하나만 연다. 앱 실행 시트는 기기 상태와 관계없이
/// 첫 await 전에 열고(시트가 창을 막아 다른 시트·확인이 끼어들지 않는다), 꺼진 기기면 시트가 "켜는 중" 을 보이는 동안 App 이
/// 주입한 `prepareRequested`(→ `LauncherModel.launchAppPreparationRequested(_:)`: 진행 기록 `.boot` 로 켜기)를 기다린 뒤
/// 그 기기의 사용자 설치 앱 목록을 읽는다 (목록 읽기는 진행 기록 없이. 기기를 바꾸지 않는다). 실패는 시트 안에 보인다.
/// 확정한 앱·링크는 `launchRequested`·`openURLRequested` 로 기기 목록 화면(`LauncherModel.launchAppRequested(_:)`·
/// `openURLRequested(_:)`)에 넘기고, 대상 재확인·진행 기록·실행은 그쪽이 한다. 목록 읽기라는 자기 비동기 흐름이 있고
/// `LauncherModel.swift` 가 600 줄에 닿아 `LauncherModel` 과 나눴다 (ARCHITECTURE §1, Android 의 `AndroidAppSheetsModel` 과 같은
/// 모양).
/// 서로 막기: 시트를 열 기기는 App 이 `LauncherModel.appSheetTarget(_:for:)` 로 잇는 `target` 이 정하고(목록·기기·작업 시작
/// 가능·다른 시트와 확인 대화상자 없음), `LauncherModel` 은 App 이 이 Model 과 테스트 조건 시트(`TestConditionsModel`)의
/// `hasPresentedSheet` 를 OR 로 잇는 클로저로 두 시트가 떠 있는지 본다 (테스트 조건 시트를 열 기기 `testConditionsTarget` 도
/// 그 클로저를 봐 이 시트가 떠 있으면 열지 않는다. 반대 방향은 시트가 창을 막는 모달이라는 점에 기댄다).
@MainActor
@Observable
public final class LauncherAppSheetsModel {
  /// 앱 실행 시트 초안(켜기·목록 읽기 상태와 읽은 목록 포함). nil 이면 시트가 닫혀 있다.
  public private(set) var launchAppDraft: LaunchAppDraft?
  /// 링크 열기 시트 초안. nil 이면 시트가 닫혀 있다.
  public private(set) var openURLDraft: OpenURLDraft?

  @ObservationIgnored private let simulator: any SimulatorClient
  /// 그 작업의 시트를 열 수 있는 기기 (없으면 nil). App 이 `LauncherModel.appSheetTarget(_:for:)` 로 잇는다.
  @ObservationIgnored private let target: @MainActor (VirtualDevice.ID, DeviceTask) -> VirtualDevice?
  /// 앱 실행 시트의 준비: 꺼져 있으면 켜고 기다린다. 켜진 기기면 곧바로 nil, 실패면 시트에 보일 실패.
  /// App 이 `LauncherModel.launchAppPreparationRequested(_:)` 로 잇는다.
  @ObservationIgnored private let prepareRequested: @MainActor (VirtualDevice.ID) async -> LaunchAppPreparationFailure?
  /// 기기 목록 다시 읽기. 목록 읽기가 실패하면(앱 밖에서 끄거나 지움) 행 상태를 맞춘다. App 이 `LauncherModel.refreshButtonTapped()` 로 잇는다.
  @ObservationIgnored private let refreshRequested: @MainActor () async -> Void
  /// 앱 실행 시트의 "실행". App 이 `LauncherModel.launchAppRequested(_:)` 로 잇는다.
  @ObservationIgnored private let launchRequested: @MainActor (LaunchAppRequest) async -> Void
  /// 링크 열기 시트의 "열기". App 이 `LauncherModel.openURLRequested(_:)` 로 잇는다.
  @ObservationIgnored private let openURLRequested: @MainActor (OpenURLRequest) async -> Void
  /// 앱 실행 시트의 준비·목록 읽기 번호. 늦게 온 앞 결과를 버리는 기준이다.
  @ObservationIgnored private var nextLaunchListRequest = 0

  public init(
    simulator: any SimulatorClient,
    target: @escaping @MainActor (VirtualDevice.ID, DeviceTask) -> VirtualDevice?,
    prepareRequested: @escaping @MainActor (VirtualDevice.ID) async -> LaunchAppPreparationFailure? = { _ in nil },
    refreshRequested: @escaping @MainActor () async -> Void = {},
    launchRequested: @escaping @MainActor (LaunchAppRequest) async -> Void = { _ in },
    openURLRequested: @escaping @MainActor (OpenURLRequest) async -> Void = { _ in }
  ) {
    self.simulator = simulator
    self.target = target
    self.prepareRequested = prepareRequested
    self.refreshRequested = refreshRequested
    self.launchRequested = launchRequested
    self.openURLRequested = openURLRequested
  }

  /// 앱 실행·링크 열기 시트가 떠 있다. App 이 `LauncherModel` 의 `appSheetPresented` 로 잇는다.
  public var hasPresentedSheet: Bool {
    self.launchAppDraft != nil || self.openURLDraft != nil
  }

  // MARK: - 앱 실행

  /// 앱 실행 시트를 첫 await 전에 열고, 꺼진 기기면 켠 뒤 그 기기의 사용자 설치 앱 목록을 읽는다.
  public func launchAppTapped(_ id: VirtualDevice.ID) async {
    guard !self.hasPresentedSheet, let device = self.target(id, .launchApp) else { return }
    self.nextLaunchListRequest += 1
    let request = self.nextLaunchListRequest
    // 첫 await 전에 연다: 시트가 창을 막아 그 뒤 다른 시트·확인이 새로 끼어들 수 없다 (늦게 여는 시트가 없다).
    self.launchAppDraft = LaunchAppDraft(
      deviceID: id,
      device: LauncherNotice.Device(device),
      request: request,
      booting: device.state == .shutdown
    )
    await self.prepareAndLoad(on: id, request: request)
  }

  /// 준비·목록 읽기가 실패한 시트의 "다시 시도". 준비부터 한다 (그사이 꺼졌으면 다시 켠다).
  public func launchAppRetryTapped() async {
    guard let draft = self.launchAppDraft, case .failed = draft.apps else { return }
    self.nextLaunchListRequest += 1
    let request = self.nextLaunchListRequest
    // 시트를 열 수 없는 기기(켜는 중·없어짐)면 `.loading` 으로 두고, 준비가 그 이유를 실패로 돌려준다.
    let booting = self.target(draft.deviceID, .launchApp)?.state == .shutdown
    self.launchAppDraft?.reloadStarted(request: request, booting: booting)
    await self.prepareAndLoad(on: draft.deviceID, request: request)
  }

  public func launchAppSelectionChanged(_ bundleID: AppBundleID?) {
    self.launchAppDraft?.selectionChanged(bundleID)
  }

  public func launchAppCancelTapped() {
    self.launchAppDraft = nil
  }

  public func launchAppSheetDismissed() {
    self.launchAppDraft = nil
  }

  /// 시트를 닫고 고른 앱의 실행을 요청한다. 실행이 끝날 때까지 기다린다.
  public func launchAppConfirmTapped() async {
    guard let draft = self.launchAppDraft, let app = draft.selectedApp else { return }
    // 첫 await 전에 닫아, 연타해도 두 번째 호출은 위에서 끝난다.
    self.launchAppDraft = nil
    await self.launchRequested(LaunchAppRequest(deviceID: draft.deviceID, device: draft.device, app: app))
  }

  // MARK: - 링크 열기

  /// 행의 "링크 열기…": 링크를 열 수 있는 기기이고 다른 시트·확인 대화상자가 없으면 시트를 연다.
  public func openURLTapped(_ id: VirtualDevice.ID) {
    guard !self.hasPresentedSheet, let device = self.target(id, .openURL) else { return }
    self.openURLDraft = OpenURLDraft(deviceID: id, device: LauncherNotice.Device(device))
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
    // 첫 await 전에 닫아, 연타해도 두 번째 호출은 위에서 끝난다.
    self.openURLDraft = nil
    await self.openURLRequested(OpenURLRequest(deviceID: draft.deviceID, device: draft.device, link: link))
  }

  // MARK: - 내부

  /// 준비(꺼져 있으면 켜기)를 기다린 뒤 목록을 읽는다. 결과는 초안이 아직 이 번호를 기다릴 때만 반영한다
  /// (닫혔거나 다시 시도·다시 열었으면 버리고, 켜는 중에 닫았으면 목록을 읽지 않는다).
  private func prepareAndLoad(on id: VirtualDevice.ID, request: Int) async {
    if let failure = await self.prepareRequested(id) {
      self.launchAppDraft?.appsLoaded(.failure(failure), request: request)
      return
    }
    self.launchAppDraft?.loadingStarted(request: request)
    guard self.launchAppDraft?.request == request else { return }
    await self.loadApps(on: id, request: request)
  }

  /// 목록을 읽어 반영한다. 실패면 반영하기 전에 기기 목록을 다시 읽어(앱 밖에서 끄거나 지운 기기의 행을 맞춰) "다시 시도" 의
  /// 준비가 다시 읽은 목록으로 켤지 정하게 한다. 실패는 시트에만 보이고 알림을 쌓지 않는다.
  private func loadApps(on id: VirtualDevice.ID, request: Int) async {
    let result: Result<[InstalledApp], LaunchAppPreparationFailure>
    do throws(SimulatorError) {
      result = try await .success(self.simulator.installedApps(on: id))
    } catch {
      await self.refreshRequested()
      result = .failure(LaunchAppPreparationFailure(.simulator(error), stage: .list))
    }
    self.launchAppDraft?.appsLoaded(result, request: request)
  }
}

/// `LauncherAppSheetsModel` 이 App 을 거쳐 `LauncherModel.launchAppRequested(_:)` 에 넘기는 설치된 앱 실행 요청.
public struct LaunchAppRequest: Hashable, Sendable {
  public let deviceID: VirtualDevice.ID
  /// 시트를 연 시점의 기기 라벨 (알림에 쓴다).
  public let device: LauncherNotice.Device
  public let app: InstalledApp

  public init(deviceID: VirtualDevice.ID, device: LauncherNotice.Device, app: InstalledApp) {
    self.deviceID = deviceID
    self.device = device
    self.app = app
  }
}

/// `LauncherAppSheetsModel` 이 App 을 거쳐 `LauncherModel.openURLRequested(_:)` 에 넘기는 링크 열기 요청.
public struct OpenURLRequest: Hashable, Sendable {
  public let deviceID: VirtualDevice.ID
  /// 시트를 연 시점의 기기 라벨 (알림에 쓴다).
  public let device: LauncherNotice.Device
  public let link: DeepLink

  public init(deviceID: VirtualDevice.ID, device: LauncherNotice.Device, link: DeepLink) {
    self.deviceID = deviceID
    self.device = device
    self.link = link
  }
}
