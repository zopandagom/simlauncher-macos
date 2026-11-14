import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

/// 테스트 조건 시트의 위치(입력·프리셋·한 점·경로·시나리오·지우기·보낸 기록)와 시트 열기 조건(다른 시트·확인·작업).
@MainActor
struct TestConditionsLocationTests: TestConditionsTesting {
  private let id = SampleID.iPhoneOn

  private static func locationCalls(_ fake: SimulatorClientFake) -> [IOSLocationSimulation] {
    self.conditionCalls(fake).compactMap {
      if case let .simulateLocation(simulation, _) = $0 {
        simulation
      } else {
        nil
      }
    }
  }

  // MARK: - 입력

  @Test("입력 변경 이벤트가 초안의 입력란·속도·시나리오를 바꾸고 명령은 없다")
  func inputEventsChangeDraft() async {
    let loaded = await Self.conditionsModels()
    let conditions = loaded.conditions
    await conditions.testConditionsTapped(self.id)
    conditions.pointTextChanged("1, 2")
    conditions.routeTextChanged("1,2\n3,4")
    conditions.routeSpeedChanged(.highway)
    conditions.scenarioChanged(.freewayDrive)

    #expect(conditions.draft?.pointText == "1, 2")
    #expect(conditions.draft?.routeText == "1,2\n3,4")
    #expect(conditions.draft?.routeSpeed == .highway)
    #expect(conditions.draft?.scenario == .freewayDrive)
    #expect(Self.locationCalls(loaded.simulator).isEmpty)
  }

  @Test("새 시트의 입력 기본값: 빈 입력란, 걷기, 도시 달리기. 빈 입력은 문제 문구 없이 버튼만 끈다")
  func draftDefaults() async {
    let loaded = await Self.conditionsModels()
    await loaded.conditions.testConditionsTapped(self.id)
    let draft = loaded.conditions.draft

    #expect(draft?.pointText.isEmpty == true)
    #expect(draft?.routeSpeed == .walking)
    #expect(draft?.scenario == .cityRun)
    #expect(draft?.pointCoordinate == nil)
    #expect(draft?.pointProblem == nil)
    #expect(draft?.routeWaypoints == nil)
    #expect(draft?.routeProblem == nil)
  }

  @Test("프리셋은 입력란을 마침표 소수점 \"위도, 경도\" 로 채우기만 한다")
  func presetFillsField() async {
    let loaded = await Self.conditionsModels()
    await loaded.conditions.testConditionsTapped(self.id)
    loaded.conditions.locationPresetSelected(.sydney)

    #expect(loaded.conditions.draft?.pointText == "-33.8688, 151.2093")
    #expect(loaded.conditions.draft?.pointCoordinate == LocationPreset.sydney.coordinate)
    #expect(Self.locationCalls(loaded.simulator).isEmpty)
  }

  @Test("잘못된 좌표·경로는 문제를 보이고 보내지 않는다")
  func invalidInputSendsNothing() async {
    let loaded = await Self.conditionsModels()
    let conditions = loaded.conditions
    await conditions.testConditionsTapped(self.id)
    conditions.pointTextChanged("37,5665, 126,9780")
    conditions.routeTextChanged("1,2")
    await conditions.setPointTapped()
    await conditions.startRouteTapped()

    #expect(conditions.draft?.pointProblem == .format)
    #expect(conditions.draft?.routeProblem == .tooFewWaypoints)
    #expect(Self.locationCalls(loaded.simulator).isEmpty)

    conditions.pointTextChanged("95, 10")
    conditions.routeTextChanged("1,2\nabc")
    #expect(conditions.draft?.pointProblem == .latitudeOutOfRange)
    #expect(conditions.draft?.routeProblem == .line(number: 2, .format))
  }

  // MARK: - 보내기

  @Test("한 점을 보내면 기록과 시각이 남고 입력란은 그대로다")
  func pointRecordsSent() async throws {
    let loaded = await Self.conditionsModels()
    let conditions = loaded.conditions
    await conditions.testConditionsTapped(self.id)
    conditions.pointTextChanged("-33.8688,151.2093")
    await conditions.setPointTapped()

    let coordinate = try #require(GeoCoordinate(latitude: -33.8688, longitude: 151.2093))
    #expect(Self.locationCalls(loaded.simulator) == [.point(coordinate)])
    #expect(conditions.sentLocations[self.id] == SentLocation(kind: .point(coordinate), sentAt: Self.fixedNow))
    #expect(conditions.draft?.pointText == "-33.8688,151.2093")
    #expect(conditions.applying.isEmpty)
  }

  @Test("경로는 고른 속도로 보내고 지점 수·속도를 기록한다")
  func routeRecordsSent() async throws {
    let loaded = await Self.conditionsModels()
    let conditions = loaded.conditions
    await conditions.testConditionsTapped(self.id)
    conditions.routeTextChanged("37.5665, 126.9780\r\n\n37.5700, 126.9800\n")
    conditions.routeSpeedChanged(.cycling)
    await conditions.startRouteTapped()

    let waypoints = try [
      #require(GeoCoordinate(latitude: 37.5665, longitude: 126.9780)),
      #require(GeoCoordinate(latitude: 37.5700, longitude: 126.9800)),
    ]
    #expect(Self.locationCalls(loaded.simulator) == [.route(LocationRoute(waypoints: waypoints, speed: .cycling))])
    #expect(conditions.sentLocations[self.id]?.kind == .route(waypointCount: 2, speed: .cycling))
  }

  @Test("시나리오·지우기를 보내면 각각 기록한다")
  func scenarioAndClearRecordSent() async {
    let loaded = await Self.conditionsModels()
    let conditions = loaded.conditions
    await conditions.testConditionsTapped(self.id)
    conditions.scenarioChanged(.cityBicycleRide)
    await conditions.runScenarioTapped()
    #expect(conditions.sentLocations[self.id]?.kind == .scenario(.cityBicycleRide))

    await conditions.clearLocationTapped()
    #expect(conditions.sentLocations[self.id]?.kind == .cleared)
    #expect(Self.locationCalls(loaded.simulator) == [.scenario(.cityBicycleRide), .clear])
  }

  @Test("시나리오가 없으면 알리고 앞 기록은 그대로다")
  func scenarioUnavailable() async {
    let loaded = await Self.conditionsModels()
    let conditions = loaded.conditions
    await conditions.testConditionsTapped(self.id)
    await conditions.clearLocationTapped()
    loaded.simulator.setScenarioUnavailable(true)
    await conditions.runScenarioTapped()

    #expect(conditions.draft?.message == .scenarioUnavailable)
    #expect(conditions.sentLocations[self.id]?.kind == .cleared)
  }

  @Test("위치 실패는 알리고 기기 목록을 다시 읽으며 기록은 그대로다")
  func locationFailure() async {
    let loaded = await Self.conditionsModels { $0.setLocationError(.deviceNotFound) }
    let conditions = loaded.conditions
    await conditions.testConditionsTapped(self.id)
    await conditions.clearLocationTapped()

    #expect(conditions.draft?.message == .failed(.location, .deviceNotFound))
    #expect(conditions.sentLocations[self.id] == nil)
    #expect(Self.fetchCount(loaded.simulator) == 2)
  }

  @Test("화면 설정을 읽지 못했거나 읽는 중이어도 위치는 보낼 수 있다")
  func locationWorksWithoutDisplay() async {
    let loaded = await Self.conditionsModels { $0.setDisplaySettingsError(.commandFailed) }
    let conditions = loaded.conditions
    await conditions.testConditionsTapped(self.id)
    #expect(conditions.draft?.display == .failed(.commandFailed))
    await conditions.clearLocationTapped()
    #expect(conditions.sentLocations[self.id]?.kind == .cleared)
  }

  @Test("위치를 보내는 중에 시트를 닫아도 성공하면 기록한다")
  func closeWhileSendingStillRecords() async {
    let loaded = await Self.conditionsModels()
    let conditions = loaded.conditions
    await conditions.testConditionsTapped(self.id)
    loaded.simulator.suspendConditions()
    let send = Self.start { await conditions.clearLocationTapped() }
    await Self.waitUntil { conditions.applying[self.id] == .location }
    // 보내는 중에는 같은 기기의 다른 위치 명령을 막는다.
    let second = Self.start { await conditions.runScenarioTapped() }
    await Self.waitUntil { second.isFinished }
    conditions.sheetDismissed()

    loaded.simulator.resumeConditions()
    await send.value()
    #expect(conditions.draft == nil)
    #expect(conditions.applying.isEmpty)
    #expect(conditions.sentLocations[self.id]?.kind == .cleared)
    #expect(Self.locationCalls(loaded.simulator) == [.clear])
  }

  // MARK: - 열기 조건

  @Test("켜진 기기는 작업이 없거나 앱 설치·링크 열기·앱 실행 중이면 열 수 있고, 켜기·끄기·삭제·초기화 중이면 열 수 없다")
  func canOpenTable() {
    let states: [VirtualDevice.State] = [.shutdown, .booted, .booting, .shuttingDown, .unknown]
    for state in states {
      for isAvailable in [true, false] {
        let device = Self.sampleDevice(state: state, isAvailable: isAvailable)
        let expected = isAvailable && state == .booted
        #expect(TestConditionsAvailability.canOpen(device: device, during: nil) == expected, "\(state) \(isAvailable)")
      }
    }
    let booted = Self.sampleDevice(state: .booted)
    for task in [DeviceTask.installApp, .openURL, .launchApp] {
      #expect(TestConditionsAvailability.canOpen(device: booted, during: task))
    }
    for task in [DeviceTask.boot, .shutdown, .delete, .erase] {
      #expect(!TestConditionsAvailability.canOpen(device: booted, during: task))
    }
  }

  @Test("앱 실행·링크 열기 시트, URL 설치 시트, 확인 대화상자가 있으면 테스트 조건 시트를 열 기기가 없다")
  func targetBlockedByOtherSheets() async {
    let loaded = await Self.conditionsModels()
    let model = loaded.model
    #expect(model.testConditionsTarget(self.id)?.id == self.id)

    loaded.sheets.openURLTapped(self.id)
    #expect(model.testConditionsTarget(self.id) == nil)
    loaded.sheets.openURLCancelTapped()

    model.installFromURLMenuTapped(self.id)
    #expect(model.testConditionsTarget(self.id) == nil)
    model.installURLSheetDismissed()

    model.eraseButtonTapped(SampleID.iPhoneOff)
    #expect(model.testConditionsTarget(self.id) == nil)
    model.confirmationDismissed()

    model.createButtonTapped()
    #expect(model.testConditionsTarget(self.id) == nil)
    model.createSheetDismissed()

    #expect(model.testConditionsTarget(self.id)?.id == self.id)
    #expect(model.testConditionsTarget(SampleID.iPhoneOff) == nil)
  }

  @Test("테스트 조건 시트가 떠 있으면 기기 목록이 만들기·URL 설치 시트를 열지 않는다")
  func conditionsSheetBlocksLauncherSheets() async {
    let loaded = await Self.conditionsModels()
    await loaded.conditions.testConditionsTapped(self.id)
    loaded.model.createButtonTapped()
    loaded.model.installFromURLMenuTapped(self.id)

    #expect(loaded.model.createDraft == nil)
    #expect(loaded.model.installURLDraft == nil)
    #expect(loaded.model.testConditionsTarget(self.id) == nil)
  }

  private static func sampleDevice(state: VirtualDevice.State, isAvailable: Bool = true) -> VirtualDevice {
    VirtualDevice(
      id: SampleID.iPhoneOn,
      name: "iPhone 17 Pro",
      family: .phone,
      state: state,
      availability: isAvailable ? .available : .unavailable(.runtimeNotInstalled),
      runtime: SampleRuntime.iOS27
    )
  }
}
