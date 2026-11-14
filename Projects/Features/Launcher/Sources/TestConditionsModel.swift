import Core
import Foundation
import Observation
import SimulatorInterface

/// iOS 기기 행 "테스트 조건…" 시트의 상태와 로직: 켜진 기기의 외관·글씨 크기·고대비(`simctl ui`)를 읽어 보이고 바꾸며, 위치
/// 한 점·경로·시나리오·지우기(`simctl location`)를 보낸다. 명령은 모두 짧게 끝나고 경로·시나리오는 기기 안에서 이어지므로
/// 이 Model 이 들고 있는 장기 작업은 없다. 시트를 닫아도 진행 중 명령은 취소하지 않고, 결과는 기기별 `applying`·`sentLocations` 에
/// 반영된다. 기기 목록 상태를 함께 쓰지 않는 자기 비동기 흐름이고 `LauncherModel.swift` 가 600 줄에 닿아 따로 둔다 (App 소유).
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

  /// 시트를 첫 await 전에 열고(시트가 창을 막아 다른 시트·확인이 끼어들지 않는다) 화면 설정의 지금 값을 읽는다.
  public func testConditionsTapped(_ id: VirtualDevice.ID) async {
    guard self.draft == nil, let device = self.target(id) else { return }
    self.nextSession += 1
    let session = self.nextSession
    self.draft = TestConditionsDraft(deviceID: id, device: LauncherNotice.Device(device), session: session)
    await self.readDisplay(on: id, session: session)
  }

  /// 읽기가 실패한 화면 구역의 "다시 읽기".
  public func displayRetryTapped() async {
    guard let draft = self.draft, case .failed = draft.display else { return }
    self.draft?.displayStarted()
    await self.readDisplay(on: draft.deviceID, session: draft.session)
  }

  /// 진행 중 명령은 취소하지 않는다 (짧게 끝나고, 결과는 `applying`·`sentLocations` 에만 반영된다).
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
  /// 있어 한 번 더 읽는다 (그래도 바뀌면 그 결과를 쓴다: 그 뒤 쓰기는 자기 결과로 표시를 고친다).
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
    self.draft?.messageChanged(nil)
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
    self.draft?.messageChanged(nil)
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
