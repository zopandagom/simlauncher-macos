import Core
import Foundation
import Observation
import SimulatorInterface

/// iOS 기기 행 "테스트 조건…" 시트의 상태와 로직: 켜진 기기의 외관·글씨 크기·고대비(`simctl ui`)를 읽어 보이고 바꾸며, 위치
/// 한 점·경로·시나리오·지우기(`simctl location`)를 보낸다. 앱 단위 구역에서는 사용자 설치 앱 목록(`installedApps`)을 읽어 앱을
/// 고르고, 그 앱의 개인정보 접근을 바꾸며(`simctl privacy`) 푸시 알림을 보낸다(`simctl push`). 명령은 모두 짧게 끝나고
/// 경로·시나리오는 기기 안에서 이어지므로 이 Model 이 들고 있는 장기 작업은 없다. 시트를 닫아도 진행 중 명령은 취소하지 않고,
/// 결과는 기기별 `applying`·`sentLocations`·`privacyHistory` 에 반영된다. 기기 목록 상태를 함께 쓰지 않는 자기 비동기
/// 흐름이고 `LauncherModel.swift` 가 600 줄에 닿아 따로 둔다 (App 소유).
/// 서로 막기: 시트를 열 기기는 App 이 `LauncherModel.testConditionsTarget(_:)` 로 잇는 `target` 이 정하고(목록·기기·켜짐·
/// 다른 시트와 확인 대화상자 없음), `LauncherModel` 은 App 이 이 Model 의 `hasPresentedSheet` 를 앱 실행·링크 열기 시트와
/// OR 로 잇는 클로저로 이 시트가 떠 있는지 본다.
@MainActor
@Observable
public final class TestConditionsModel {
  /// 시트 초안. nil 이면 시트가 닫혀 있다.
  public private(set) var draft: TestConditionsDraft?
  /// 기기별 적용 중인 항목 (한 기기에 하나). 시트를 닫았다 다시 열어도 같은 기기의 두 번째 명령을 막도록 초안 밖에 둔다.
  public private(set) var applying: [VirtualDevice.ID: TestConditionItem] = [:]
  /// SimLauncher 가 켜져 있는 동안 기기별로 마지막으로 보낸 위치. 앱을 다시 켜면 비어 있다 (저장하지 않는다).
  public private(set) var sentLocations: [VirtualDevice.ID: SentLocation] = [:]
  /// SimLauncher 가 켜져 있는 동안 기기·앱별로 마지막으로 성공한 개인정보 접근 바꾸기. iOS 는 지금 상태를 알려 주지 않아 이 기록만
  /// 보인다. 저장하지 않고, 기기를 끄거나 초기화해도 지우지 않는다 (위치 기록과 같은 규칙, 시트가 안내한다).
  public private(set) var privacyHistory: [VirtualDevice.ID: [AppBundleID: [IOSPrivacyService: IOSPrivacyAction]]] = [:]

  @ObservationIgnored private let simulator: any SimulatorClient
  /// 시트를 열 수 있는 기기 (없으면 nil). App 이 `LauncherModel.testConditionsTarget(_:)` 로 잇는다.
  @ObservationIgnored private let target: @MainActor (VirtualDevice.ID) -> VirtualDevice?
  /// 기기 목록 다시 읽기. 명령이 기기 꺼짐·없어짐으로 실패하면 행 상태를 맞춘다. App 이 `LauncherModel.refreshButtonTapped()` 로 잇는다.
  @ObservationIgnored private let refreshRequested: @MainActor () async -> Void
  /// 보낸 위치의 시각.
  @ObservationIgnored private let now: @Sendable () -> Date
  /// 마지막으로 연 시트의 번호.
  @ObservationIgnored private var nextSession = 0
  /// 기기별로 끝난 화면 설정 쓰기 횟수. 읽는 동안 쓰기가 끝났으면 그 읽기는 쓰기 전 값일 수 있어 다시 읽는다.
  @ObservationIgnored private var settingsEpoch: [VirtualDevice.ID: Int] = [:]
  /// 기기별로 사용자가 마지막으로 고른 앱. 같은 기기의 시트를 다시 열면 그 앱을 먼저 고른다 (SimLauncher 가 켜져 있는 동안).
  @ObservationIgnored private var lastSelectedApp: [VirtualDevice.ID: AppBundleID] = [:]

  public init(
    simulator: any SimulatorClient,
    target: @escaping @MainActor (VirtualDevice.ID) -> VirtualDevice?,
    refreshRequested: @escaping @MainActor () async -> Void = {},
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.simulator = simulator
    self.target = target
    self.refreshRequested = refreshRequested
    self.now = now
  }

  /// 테스트 조건 시트가 떠 있다. App 이 `LauncherModel` 의 `appSheetPresented` 에 OR 로 잇는다.
  public var hasPresentedSheet: Bool {
    self.draft != nil
  }

  // MARK: - 열기·닫기

  /// 시트를 첫 await 전에 열고(시트가 창을 막아 다른 시트·확인이 끼어들지 않는다) 화면 설정의 지금 값을 읽은 뒤 설치된 앱 목록을
  /// 읽는다. 화면 읽기가 기기 꺼짐·없어짐으로 실패했으면 목록은 읽지 않고 같은 실패를 보인다 (목록 새로 고침은 화면 읽기에서 한 번).
  public func testConditionsTapped(_ id: VirtualDevice.ID) async {
    guard self.draft == nil, let device = self.target(id) else { return }
    self.nextSession += 1
    let session = self.nextSession
    self.draft = TestConditionsDraft(deviceID: id, device: LauncherNotice.Device(device), session: session)
    await self.readDisplay(on: id, session: session)
    guard let draft = self.draft, draft.session == session else { return }
    if case let .failed(error) = draft.display, error == .deviceNotBooted || error == .deviceNotFound {
      self.draft?.updateApp { $0.appsFailed(error) }
      return
    }
    await self.loadApps(on: id, session: session)
  }

  /// 읽기가 실패한 화면 구역의 "다시 읽기".
  public func displayRetryTapped() async {
    guard let draft = self.draft, case .failed = draft.display else { return }
    self.draft?.displayStarted()
    await self.readDisplay(on: draft.deviceID, session: draft.session)
  }

  /// 진행 중 명령은 취소하지 않는다 (짧게 끝나고, 결과는 `applying`·`sentLocations`·`privacyHistory` 에만 반영된다).
  public func closeTapped() {
    self.draft = nil
  }

  public func sheetDismissed() {
    self.draft = nil
  }

  // MARK: - 화면

  public func appearanceSelected(_ appearance: DeviceAppearance) async {
    await self.apply(.appearance(appearance))
  }

  public func contentSizeSelected(_ size: IOSContentSize) async {
    await self.apply(.contentSize(size))
  }

  public func increaseContrastChanged(_ isOn: Bool) async {
    await self.apply(.increaseContrast(isOn))
  }

  // MARK: - 위치 입력

  public func pointTextChanged(_ text: String) {
    self.draft?.pointTextChanged(text)
  }

  /// 프리셋은 입력란을 채우기만 한다 (곧바로 보내지 않는다).
  public func locationPresetSelected(_ preset: LocationPreset) {
    let coordinate = preset.coordinate
    self.draft?.pointTextChanged(
      "\(GeoCoordinate.decimalString(coordinate.latitude)), \(GeoCoordinate.decimalString(coordinate.longitude))"
    )
  }

  public func routeTextChanged(_ text: String) {
    self.draft?.routeTextChanged(text)
  }

  public func routeSpeedChanged(_ speed: LocationRouteSpeed) {
    self.draft?.routeSpeedChanged(speed)
  }

  public func scenarioChanged(_ scenario: IOSLocationScenario) {
    self.draft?.scenarioChanged(scenario)
  }

  // MARK: - 위치 보내기

  /// 위치는 화면 구역의 읽기 상태와 관계없이 보낼 수 있다 (읽는 중·읽기 실패에도).
  public func setPointTapped() async {
    guard let coordinate = self.draft?.pointCoordinate else { return }
    await self.simulate(.point(coordinate), sent: .point(coordinate))
  }

  public func startRouteTapped() async {
    guard let draft = self.draft, let waypoints = draft.routeWaypoints else { return }
    let route = LocationRoute(waypoints: waypoints, speed: draft.routeSpeed)
    await self.simulate(.route(route), sent: .route(waypointCount: waypoints.count, speed: draft.routeSpeed))
  }

  public func runScenarioTapped() async {
    guard let scenario = self.draft?.scenario else { return }
    await self.simulate(.scenario(scenario), sent: .scenario(scenario))
  }

  public func clearLocationTapped() async {
    await self.simulate(.clear, sent: .cleared)
  }

  // MARK: - 내부

  /// 화면 설정을 읽어 반영한다. 돌아왔을 때 시트가 닫혔거나 다시 열렸으면 버린다. 읽는 동안 그 기기의 쓰기가 끝났으면 쓰기 전 값일 수
  /// 있어 한 번 더 읽는다. 읽는 동안에는 화면 설정을 바꿀 수 없고(`.loaded` 가 아님) 쓰기 결과도 읽은 값(`.loaded`)이 있을 때만
  /// 반영되어(`settingApplied`·`settingsRead`) 읽는 동안 `.loaded` 가 되지 않으므로, 겹치는 쓰기는 읽기 전에 시작한 하나뿐이라 한 번이면 된다.
  private func readDisplay(on id: VirtualDevice.ID, session: Int) async {
    var retried = false
    while true {
      let epoch = self.settingsEpoch[id, default: 0]
      let result: Result<IOSDisplaySettings, SimulatorError>
      do throws(SimulatorError) {
        result = try await .success(self.simulator.displaySettings(on: id))
      } catch {
        result = .failure(error)
      }
      guard self.draft?.session == session else { return }
      if self.settingsEpoch[id, default: 0] != epoch, !retried {
        retried = true
        continue
      }
      switch result {
      case let .success(settings):
        self.draft?.displayLoaded(settings)
      case let .failure(error):
        self.draft?.displayFailed(error)
        await self.refreshIfDeviceChanged(error)
      }
      return
    }
  }

  /// 화면 설정 하나를 보낸다. 지금 값을 읽었고(`.loaded`, 그 항목이 `.value`) 고른 값과 다르고 그 기기에 적용 중인 것이 없을 때만.
  private func apply(_ setting: IOSDisplaySetting) async {
    guard let draft = self.draft,
          case let .loaded(settings) = draft.display,
          settings.canApply(setting),
          self.applying[draft.deviceID] == nil
    else { return }
    let id = draft.deviceID
    let item = setting.item
    // 첫 await 전에 채워 연타한 두 번째 호출은 위에서 끝난다.
    self.applying[id] = item
    self.draft?.applyStarted()
    let result: Result<IOSDisplaySettingOutcome, SimulatorError>
    do throws(SimulatorError) {
      result = try await .success(self.simulator.setDisplaySetting(setting, on: id))
    } catch {
      result = .failure(error)
    }
    self.applying[id] = nil
    self.settingsEpoch[id, default: 0] += 1
    // 결과는 기기의 사실이라 같은 기기의 시트면(다시 열었어도) 반영한다.
    let isShown = self.draft?.deviceID == id
    switch result {
    case .success(.applied):
      if isShown {
        self.draft?.settingApplied(setting)
      }
    case let .success(.notApplied(read)):
      if isShown {
        self.draft?.settingsRead(read)
        self.draft?.messageChanged(read.isUnsupported(item) ? .unsupported(item) : .notApplied(item))
      }
    case let .failure(error):
      if isShown {
        self.draft?.messageChanged(.failed(item, error))
      }
      await self.refreshIfDeviceChanged(error)
    }
  }

  /// 위치를 보낸다. 성공하면 시트가 닫혔어도 기록한다 (기기에는 적용됐다). 입력란은 지우지 않는다 (같은 값으로 다시 보내기 쉽게).
  private func simulate(_ simulation: IOSLocationSimulation, sent: SentLocation.Kind) async {
    guard let id = self.draft?.deviceID, self.applying[id] == nil else { return }
    self.applying[id] = .location
    self.draft?.applyStarted()
    let result: Result<IOSLocationOutcome, SimulatorError>
    do throws(SimulatorError) {
      result = try await .success(self.simulator.simulateLocation(simulation, on: id))
    } catch {
      result = .failure(error)
    }
    self.applying[id] = nil
    let isShown = self.draft?.deviceID == id
    switch result {
    case .success(.applied):
      self.sentLocations[id] = SentLocation(kind: sent, sentAt: self.now())
    case .success(.scenarioUnavailable):
      if isShown {
        self.draft?.messageChanged(.scenarioUnavailable)
      }
    case let .failure(error):
      if isShown {
        self.draft?.messageChanged(.failed(.location, error))
      }
      await self.refreshIfDeviceChanged(error)
    }
  }

  /// 기기가 꺼졌거나 없어진 실패면 기기 목록을 다시 읽어 행 상태를 맞춘다 (알림은 쌓지 않는다).
  private func refreshIfDeviceChanged(_ error: SimulatorError) async {
    if error == .deviceNotBooted || error == .deviceNotFound {
      await self.refreshRequested()
    }
  }
}

// MARK: - 앱 단위 (앱 고르기·권한·푸시 알림)

// 타입 본문 길이(lint `type_body_length`)에 들지 않게 같은 파일의 extension 에 둔다 (같은 파일이라 `private` 상태에 닿는다).
public extension TestConditionsModel {
  /// "앱 목록 다시 읽기". 읽는 중이 아니면(읽었거나 실패했으면) 다시 읽는다. 읽는 동안 마지막 목록과 고른 앱(그 아래 권한·푸시
  /// 구역)을 그대로 두고, 고른 앱이 새 목록에 있으면 그대로 둔다.
  func appsRefreshTapped() async {
    guard let draft = self.draft, !draft.app.isReadingApps else { return }
    await self.loadApps(on: draft.deviceID, session: draft.session)
  }

  /// 앱을 고른다 (nil 이면 고르지 않음). 목록에 없는 앱은 무시한다. 마지막 결과·실패 줄은 그대로 둔다 (문구에 앱 이름이 있다).
  func appSelected(_ id: AppBundleID?) {
    guard let deviceID = self.draft?.deviceID else { return }
    var accepted = false
    self.draft?.updateApp { accepted = $0.appSelected(id) }
    guard accepted else { return }
    self.lastSelectedApp[deviceID] = id
  }

  /// 고른 앱의 개인정보 접근을 바꾼다. 위치 밖의 서비스는 실행 중인 앱을 종료한다 (시트가 늘 안내한다, 확인은 묻지 않는다).
  /// 성공하면 시트가 닫혔어도 `privacyHistory` 에 기록한다 (기기에는 적용됐다).
  func privacyTapped(_ service: IOSPrivacyService, _ action: IOSPrivacyAction) async {
    guard let draft = self.draft, let app = draft.app.selectedApp, self.applying[draft.deviceID] == nil else { return }
    let id = draft.deviceID
    let item = TestConditionItem.privacy(service)
    // 첫 await 전에 채워 연타한 두 번째 호출은 위에서 끝난다.
    self.applying[id] = item
    self.draft?.applyStarted()
    let result: Result<Void, SimulatorError>
    do throws(SimulatorError) {
      try await self.simulator.setPrivacy(action, service, for: app.bundleID, on: id)
      result = .success(())
    } catch {
      result = .failure(error)
    }
    self.applying[id] = nil
    let isShown = self.draft?.deviceID == id
    switch result {
    case .success:
      self.privacyHistory[id, default: [:]][app.bundleID, default: [:]][service] = action
      if isShown {
        self.draft?.updateApp { $0.resultChanged(.privacyChanged(service, action, appName: app.displayName)) }
      }
    case let .failure(error):
      if isShown {
        self.draft?.messageChanged(.failed(item, error))
      }
      await self.refreshIfDeviceChanged(error)
    }
  }

  func pushInputChanged(_ mode: TestConditionsAppDraft.PushInputMode) {
    self.draft?.updateApp { $0.pushInputChanged(mode) }
  }

  func pushTitleChanged(_ text: String) {
    self.draft?.updateApp { $0.pushTitleChanged(text) }
  }

  func pushBodyChanged(_ text: String) {
    self.draft?.updateApp { $0.pushBodyChanged(text) }
  }

  func pushJSONChanged(_ text: String) {
    self.draft?.updateApp { $0.pushJSONChanged(text) }
  }

  /// 고른 앱에 지금 입력의 푸시를 보낸다. 입력에 문제가 있으면 보내지 않는다. 입력은 지우지 않는다 (같은 내용을 다시 보내기 쉽게).
  func sendPushTapped() async {
    guard let draft = self.draft,
          let app = draft.app.selectedApp,
          let payload = draft.app.pushPayload,
          self.applying[draft.deviceID] == nil
    else { return }
    let id = draft.deviceID
    self.applying[id] = .push
    self.draft?.applyStarted()
    let result: Result<IOSPushOutcome, SimulatorError>
    do throws(SimulatorError) {
      result = try await .success(self.simulator.sendPush(payload, to: app.bundleID, on: id))
    } catch {
      result = .failure(error)
    }
    self.applying[id] = nil
    guard self.draft?.deviceID == id else {
      if case let .failure(error) = result {
        await self.refreshIfDeviceChanged(error)
      }
      return
    }
    switch result {
    case .success(.sent):
      self.draft?.updateApp { $0.resultChanged(.pushSent(appName: app.displayName)) }
    case .success(.notAuthorized):
      self.draft?.messageChanged(.pushNotAuthorized(appName: app.displayName))
    case .success(.noVisibleContent):
      self.draft?.messageChanged(.pushNoVisibleContent)
    case .success(.payloadRejected):
      self.draft?.messageChanged(.pushRejected)
    case let .failure(error):
      self.draft?.messageChanged(.failed(.push, error))
      await self.refreshIfDeviceChanged(error)
    }
  }

  /// 설치된 앱 목록을 읽어 반영한다. 돌아왔을 때 시트가 닫혔거나 다시 열렸거나(번호) 그 뒤 다시 읽기를 시작했으면(요청 번호) 버린다.
  private func loadApps(on id: VirtualDevice.ID, session: Int) async {
    guard self.draft?.session == session else { return }
    self.draft?.updateApp { $0.appsStarted() }
    guard let request = self.draft?.app.appsRequest else { return }
    let result: Result<[InstalledApp], SimulatorError>
    do throws(SimulatorError) {
      result = try await .success(self.simulator.installedApps(on: id))
    } catch {
      result = .failure(error)
    }
    guard let draft = self.draft, draft.session == session, draft.app.appsRequest == request else { return }
    switch result {
    case let .success(apps):
      let remembered = self.lastSelectedApp[id]
      self.draft?.updateApp { $0.appsLoaded(apps, remembered: remembered) }
    case let .failure(error):
      self.draft?.updateApp { $0.appsFailed(error) }
      await self.refreshIfDeviceChanged(error)
    }
  }
}
