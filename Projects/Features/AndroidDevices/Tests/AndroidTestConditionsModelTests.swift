import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 행 "테스트 조건…" 시트 (`AndroidTestConditionsModel`): 열기·읽기·외관·위치 한 점·겹침과 열기 조건. fixture 가 App 처럼 잇는다.
@MainActor
struct AndroidTestConditionsModelTests: AndroidDevicesTesting {
  static let tablet = AndroidVirtualDevice.bootedTabletSample
  private var id: AndroidVirtualDevice.ID {
    Self.tablet.id
  }

  private static func conditionCalls(_ fake: AndroidEmulatorClientFake) -> [AndroidEmulatorClientFake.ConditionCall] {
    fake.calls.compactMap {
      if case let .testCondition(call) = $0 {
        call
      } else {
        nil
      }
    }
  }

  private static func readCount(_ fake: AndroidEmulatorClientFake) -> Int {
    self.conditionCalls(fake).count(where: {
      if case .testConditions = $0 {
        true
      } else {
        false
      }
    })
  }

  // MARK: - 열기

  @Test("꺼진 기기는 열지 않고, 켜진 기기는 첫 await 전에 읽는 중으로 열어 읽은 값을 보인다")
  func opensAndReads() async {
    let setup = await Self.loadedFixture { $0.suspendConditions() }
    let conditions = setup.conditions
    await conditions.testConditionsTapped(AndroidVirtualDevice.phoneSample.id)
    #expect(conditions.draft == nil)

    let tap = Self.start { await conditions.testConditionsTapped(self.id) }
    await Self.waitUntil { Self.readCount(setup.fake) == 1 }
    #expect(conditions.draft?.conditions == .loading)
    #expect(conditions.draft?.device == AndroidDeviceLabel(Self.tablet))
    #expect(setup.model.hasPresentedSheet)
    #expect(!setup.model.canCreateDevice)

    setup.fake.resumeConditions()
    await tap.value()
    #expect(conditions.draft?.conditions == .loaded(AndroidEmulatorClientFake.defaultTestConditions))
    #expect(conditions.draft?.isLocationServiceOff == false)
  }

  @Test("읽기 실패를 보이고, 꺼짐이면 목록을 다시 읽으며, 다시 읽기로 다시 읽는다")
  func readFailureThenRetry() async {
    let setup = await Self.loadedFixture { $0.setTestConditionsError(.deviceNotBooted) }
    let conditions = setup.conditions
    await conditions.testConditionsTapped(self.id)
    #expect(conditions.draft?.conditions == .failed(.deviceNotBooted))
    #expect(Self.fetchCount(setup.fake) == 2)

    setup.fake.setTestConditionsError(nil)
    await conditions.conditionsRetryTapped()
    #expect(conditions.draft?.conditions == .loaded(AndroidEmulatorClientFake.defaultTestConditions))
    #expect(Self.readCount(setup.fake) == 2)
  }

  @Test("adb 문제로 읽지 못하면 목록을 다시 읽지 않는다")
  func readAdbFailureNoRefresh() async {
    let setup = await Self.loadedFixture { $0.setTestConditionsError(.adbUnavailable) }
    await setup.conditions.testConditionsTapped(self.id)
    #expect(setup.conditions.draft?.conditions == .failed(.adbUnavailable))
    #expect(Self.fetchCount(setup.fake) == 1)
  }

  @Test("위치 서비스가 꺼져 있다고 읽으면 안내를 보인다")
  func locationServiceOff() async {
    let setup = await Self.loadedFixture {
      $0.setTestConditions(
        AndroidTestConditions(nightMode: .light, locationEnabled: false),
        for: AndroidVirtualDevice.bootedTabletSample.id
      )
    }
    await setup.conditions.testConditionsTapped(self.id)
    #expect(setup.conditions.draft?.isLocationServiceOff == true)
  }

  @Test("닫은 뒤 도착한 읽기 결과는 버린다")
  func lateReadDropped() async {
    let setup = await Self.loadedFixture { $0.suspendConditions() }
    let tap = Self.start { await setup.conditions.testConditionsTapped(self.id) }
    await Self.waitUntil { Self.readCount(setup.fake) == 1 }
    setup.conditions.sheetDismissed()
    setup.fake.resumeConditions()
    await tap.value()
    #expect(setup.conditions.draft == nil)
    #expect(!setup.conditions.hasPresentedSheet)
  }

  // MARK: - 외관

  @Test("외관을 고르면 첫 await 전에 적용 중이 되고 연타는 무시되며, 끝나면 값이 바뀐다")
  func appearanceApplies() async {
    let setup = await Self.loadedFixture()
    let conditions = setup.conditions
    await conditions.testConditionsTapped(self.id)
    setup.fake.suspendConditions()
    let first = Self.start { await conditions.appearanceSelected(.dark) }
    await Self.waitUntil { conditions.applying[self.id] == .appearance }
    let second = Self.start { await conditions.appearanceSelected(.dark) }
    await Self.waitUntil { second.isFinished }
    setup.fake.resumeConditions()
    await first.value()

    #expect(Self.conditionCalls(setup.fake) == [.testConditions(self.id), .setNightMode(.dark, self.id)])
    guard case let .loaded(values) = conditions.draft?.conditions else {
      Issue.record("값이 보이지 않는다")
      return
    }
    #expect(values.nightMode == .dark)
    #expect(conditions.applying.isEmpty)
  }

  @Test("지금 값과 같은 외관은 보내지 않는다")
  func sameAppearanceDoesNothing() async {
    let setup = await Self.loadedFixture()
    await setup.conditions.testConditionsTapped(self.id)
    await setup.conditions.appearanceSelected(.light)
    #expect(Self.conditionCalls(setup.fake) == [.testConditions(self.id)])
  }

  @Test("자동·예약 모드나 읽지 못한 값에서도 외관을 고르면 보낸다", arguments: [
    AndroidNightModeReading.other, .unknown,
  ])
  func appearanceFromOtherOrUnknown(reading: AndroidNightModeReading) async {
    let setup = await Self.loadedFixture {
      $0.setTestConditions(
        AndroidTestConditions(nightMode: reading, locationEnabled: nil),
        for: AndroidVirtualDevice.bootedTabletSample.id
      )
    }
    await setup.conditions.testConditionsTapped(self.id)
    await setup.conditions.appearanceSelected(.light)
    #expect(Self.conditionCalls(setup.fake).last == .setNightMode(.light, self.id))
    guard case let .loaded(values) = setup.conditions.draft?.conditions else {
      Issue.record("값이 보이지 않는다")
      return
    }
    #expect(values.nightMode == .light)
  }

  @Test("외관이 바뀌지 않으면 알리고, 실패하면 알리며 꺼짐이면 목록을 다시 읽는다")
  func appearanceNotAppliedAndFailure() async {
    let setup = await Self.loadedFixture { $0.setNightModeResult(.success(.notApplied)) }
    let conditions = setup.conditions
    await conditions.testConditionsTapped(self.id)
    await conditions.appearanceSelected(.dark)
    #expect(conditions.draft?.message == .notApplied(.appearance))
    #expect(conditions.draft?.conditions == .loaded(AndroidEmulatorClientFake.defaultTestConditions))

    setup.fake.setNightModeResult(.failure(.deviceNotBooted))
    await conditions.appearanceSelected(.dark)
    #expect(conditions.draft?.message == .failed(.appearance, .deviceNotBooted))
    #expect(Self.fetchCount(setup.fake) == 2)
    #expect(setup.model.notices.isEmpty)
  }

  @Test("적용 중에 닫았다 다시 열면 다시 연 시트에서도 같은 기기는 막히고, 읽는 동안 끝난 쓰기 결과는 알림만 남기고 한 번 더 읽는다")
  func writeFinishedDuringReopenRead() async {
    let setup = await Self.loadedFixture()
    let conditions = setup.conditions
    let fake = setup.fake
    await conditions.testConditionsTapped(self.id)
    fake.setNightModeResult(.success(.notApplied))
    fake.suspendConditions()
    let write = Self.start { await conditions.appearanceSelected(.dark) }
    await Self.waitUntil { Self.conditionCalls(fake).count == 2 }
    conditions.closeTapped()

    fake.suspendConditionReads()
    let reopen = Self.start { await conditions.testConditionsTapped(self.id) }
    await Self.waitUntil { Self.readCount(fake) == 2 }
    conditions.pointTextChanged("37.5, 127")
    await conditions.setPointTapped()
    #expect(Self.conditionCalls(fake).count == 3)

    fake.resumeConditions()
    await write.value()
    #expect(conditions.applying.isEmpty)
    #expect(conditions.draft?.conditions == .loading)
    #expect(conditions.draft?.message == .notApplied(.appearance))

    fake.resumeConditionReads()
    await reopen.value()
    #expect(Self.readCount(fake) == 3)
    #expect(conditions.draft?.conditions == .loaded(AndroidEmulatorClientFake.defaultTestConditions))
  }

  // MARK: - 위치

  @Test("입력·프리셋은 입력란만 바꾸고, 잘못된 입력은 보내지 않는다")
  func pointInput() async {
    let setup = await Self.loadedFixture()
    let conditions = setup.conditions
    await conditions.testConditionsTapped(self.id)
    conditions.pointTextChanged("200, 37")
    #expect(conditions.draft?.pointProblem == .latitudeOutOfRange)
    await conditions.setPointTapped()
    conditions.pointTextChanged("")
    #expect(conditions.draft?.pointProblem == nil)
    conditions.locationPresetSelected(.cupertino)
    #expect(conditions.draft?.pointText == "37.3349, -122.009")
    #expect(Self.conditionCalls(setup.fake) == [.testConditions(self.id)])
  }

  @Test("한 점을 보내면 기록하고, 받지 않으면 알리고 기록은 그대로이며, 읽기 실패 상태에서도 보낼 수 있다")
  func pointSend() async throws {
    let setup = await Self.loadedFixture { $0.setTestConditionsError(.adbUnavailable) }
    let conditions = setup.conditions
    await conditions.testConditionsTapped(self.id)
    conditions.pointTextChanged("37.5665, 126.9780")
    await conditions.setPointTapped()

    let coordinate = try #require(GeoCoordinate(latitude: 37.5665, longitude: 126.9780))
    #expect(Self.conditionCalls(setup.fake).last == .setLocation(coordinate, self.id))
    #expect(conditions.sentLocations[self.id] == AndroidSentLocation(coordinate: coordinate, sentAt: fixedNow))
    #expect(conditions.draft?.pointText == "37.5665, 126.9780")

    setup.fake.setLocationResult(.success(.notApplied))
    conditions.pointTextChanged("1, 2")
    await conditions.setPointTapped()
    #expect(conditions.draft?.message == .notApplied(.location))
    #expect(conditions.sentLocations[self.id]?.coordinate == coordinate)
  }

  @Test("위치를 보내는 중에 닫아도 성공하면 기록한다")
  func closeWhileSending() async {
    let setup = await Self.loadedFixture()
    let conditions = setup.conditions
    await conditions.testConditionsTapped(self.id)
    conditions.locationPresetSelected(.seoul)
    setup.fake.suspendConditions()
    let send = Self.start { await conditions.setPointTapped() }
    await Self.waitUntil { conditions.applying[self.id] == .location }
    conditions.closeTapped()
    setup.fake.resumeConditions()
    await send.value()
    #expect(conditions.sentLocations[self.id]?.coordinate == LocationPreset.seoul.coordinate)
    #expect(conditions.applying.isEmpty)
  }

  // MARK: - 열기 조건

  @Test("켜진 기기는 작업이 없거나 앱 설치·실행·링크 열기 중이면 열 수 있고, 켜기·끄기·삭제·초기화 중이면 열 수 없다")
  func canOpenTable() {
    let booted = Self.tablet
    #expect(AndroidTestConditionsAvailability.canOpen(device: booted, during: nil))
    for task in [AndroidDeviceTask.installApp, .launchApp, .openURL] {
      #expect(AndroidTestConditionsAvailability.canOpen(device: booted, during: task))
    }
    for task in [AndroidDeviceTask.boot, .shutdown, .delete, .erase] {
      #expect(!AndroidTestConditionsAvailability.canOpen(device: booted, during: task))
    }
    #expect(!AndroidTestConditionsAvailability.canOpen(device: .phoneSample, during: nil))
    #expect(!AndroidTestConditionsAvailability.canOpen(device: .bootingSample, during: nil))
    #expect(!AndroidTestConditionsAvailability.canOpen(device: .unsupportedNameSample, during: nil))
  }

  @Test("앱 실행·링크 열기 시트, 만들기 시트, 확인 대화상자가 있으면 열 기기가 없고, 테스트 조건 시트가 있으면 만들기를 열지 않는다")
  func targetBlockedByOtherSheets() async {
    let setup = await Self.loadedFixture()
    let model = setup.model
    #expect(model.testConditionsTarget(self.id)?.id == self.id)

    setup.sheets.openURLTapped(self.id)
    #expect(model.testConditionsTarget(self.id) == nil)
    setup.sheets.openURLSheetDismissed()

    model.createButtonTapped()
    #expect(model.testConditionsTarget(self.id) == nil)
    model.creationSheetDismissed()

    model.eraseTapped(AndroidVirtualDevice.phoneSample.id)
    #expect(model.testConditionsTarget(self.id) == nil)
    model.confirmationCancelled()
    #expect(model.testConditionsTarget(self.id)?.id == self.id)

    await setup.conditions.testConditionsTapped(self.id)
    model.createButtonTapped()
    #expect(model.creationDraft == nil)
    #expect(model.testConditionsTarget(self.id) == nil)
  }
}
