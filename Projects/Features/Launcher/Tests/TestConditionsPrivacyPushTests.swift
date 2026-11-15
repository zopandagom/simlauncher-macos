import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

/// 테스트 조건 시트의 앱 단위 구역: 권한(`setPrivacy`)·푸시(`sendPush`)와 다른 적용과의 겹침. 앱 목록은 `TestConditionsAppTests`.
@MainActor
struct TestConditionsPrivacyPushTests: TestConditionsAppTesting {
  private let id = SampleID.iPhoneOn

  // MARK: - 권한

  @Test("앱을 고르지 않았으면 권한을 바꾸지 않는다")
  func privacyNeedsApp() async {
    let loaded = await Self.conditionsModels { $0.setInstalledApps([Self.sample, Self.rig], on: SampleID.iPhoneOn) }
    await loaded.conditions.testConditionsTapped(self.id)
    await loaded.conditions.privacyTapped(.camera, .grant)
    #expect(Self.privacyCalls(loaded.simulator).isEmpty)
  }

  @Test("권한을 바꾸면 첫 await 전에 적용 중이 되고, 성공하면 기록과 성공 줄을 남긴다")
  func privacySucceeds() async {
    let loaded = await Self.openedWithSample()
    let conditions = loaded.conditions
    loaded.simulator.suspendConditions()
    let tap = Self.start { await conditions.privacyTapped(.camera, .grant) }
    await Self.waitUntil { !Self.privacyCalls(loaded.simulator).isEmpty }
    #expect(conditions.applying[self.id] == .privacy(.camera))

    loaded.simulator.resumeConditions()
    await tap.value()
    #expect(Self.privacyCalls(loaded.simulator) == [.setPrivacy(.grant, .camera, Self.sample.bundleID, self.id)])
    #expect(conditions.applying.isEmpty)
    #expect(conditions.privacyHistory[self.id]?[Self.sample.bundleID] == [.camera: .grant])
    #expect(conditions.draft?.app.result == .privacyChanged(.camera, .grant, appName: "Sample"))
    #expect(conditions.draft?.message == nil)

    await conditions.privacyTapped(.camera, .reset)
    #expect(conditions.privacyHistory[self.id]?[Self.sample.bundleID] == [.camera: .reset])
  }

  @Test("적용 중에는 다른 권한·푸시·화면·위치 적용을 보내지 않는다")
  func applyingBlocksOthers() async {
    let loaded = await Self.openedWithSample()
    let conditions = loaded.conditions
    conditions.pointTextChanged("37.5, 127.0")
    loaded.simulator.suspendConditions()
    let first = Self.start { await conditions.privacyTapped(.camera, .grant) }
    await Self.waitUntil { !Self.privacyCalls(loaded.simulator).isEmpty }

    let others: [TrackedTask] = [
      Self.start { await conditions.privacyTapped(.microphone, .revoke) },
      Self.start { await conditions.sendPushTapped() },
      Self.start { await conditions.appearanceSelected(.dark) },
      Self.start { await conditions.setPointTapped() },
    ]
    await Self.waitUntil { others.allSatisfy(\.isFinished) }
    // 적용 중에도 앱 고르기는 된다.
    conditions.appSelected(Self.rig.bundleID)
    #expect(conditions.draft?.app.selectedAppID == Self.rig.bundleID)

    loaded.simulator.resumeConditions()
    await first.value()
    #expect(Self.conditionCalls(loaded.simulator).count == 2)
  }

  @Test("권한을 바꾸는 중에 다른 앱을 골라도 성공 줄의 앱 이름은 시작한 때의 앱이고, 기록도 그 앱에 남는다")
  func privacyResultUsesStartApp() async {
    let loaded = await Self.openedWithSample()
    let conditions = loaded.conditions
    loaded.simulator.suspendConditions()
    let tap = Self.start { await conditions.privacyTapped(.photos, .revoke) }
    await Self.waitUntil { !Self.privacyCalls(loaded.simulator).isEmpty }
    conditions.appSelected(Self.rig.bundleID)
    loaded.simulator.resumeConditions()
    await tap.value()

    #expect(conditions.draft?.app.result == .privacyChanged(.photos, .revoke, appName: "Sample"))
    #expect(conditions.privacyHistory[self.id]?[Self.sample.bundleID] == [.photos: .revoke])
    #expect(conditions.privacyHistory[self.id]?[Self.rig.bundleID] == nil)
  }

  @Test("시트를 닫은 뒤 끝난 권한 바꾸기도 기록하고, 다시 연 같은 기기의 시트에 성공 줄을 보인다")
  func privacyAfterCloseRecordedAndShown() async {
    let loaded = await Self.openedWithSample()
    let conditions = loaded.conditions
    loaded.simulator.suspendConditions()
    let tap = Self.start { await conditions.privacyTapped(.contacts, .grant) }
    await Self.waitUntil { !Self.privacyCalls(loaded.simulator).isEmpty }
    conditions.closeTapped()
    let reopen = Self.start { await conditions.testConditionsTapped(self.id) }
    await Self.waitUntil { conditions.draft?.session == 2 }
    #expect(conditions.applying[self.id] == .privacy(.contacts))

    loaded.simulator.resumeConditions()
    await tap.value()
    await reopen.value()
    #expect(conditions.privacyHistory[self.id]?[Self.sample.bundleID] == [.contacts: .grant])
    #expect(conditions.draft?.app.result == .privacyChanged(.contacts, .grant, appName: "Sample"))
  }

  @Test("닫힌 채 끝난 권한 바꾸기는 기록만 남는다")
  func privacyAfterCloseOnlyRecorded() async {
    let loaded = await Self.openedWithSample()
    let conditions = loaded.conditions
    loaded.simulator.suspendConditions()
    let tap = Self.start { await conditions.privacyTapped(.motion, .reset) }
    await Self.waitUntil { !Self.privacyCalls(loaded.simulator).isEmpty }
    conditions.sheetDismissed()
    loaded.simulator.resumeConditions()
    await tap.value()
    #expect(conditions.draft == nil)
    #expect(conditions.privacyHistory[self.id]?[Self.sample.bundleID] == [.motion: .reset])
    #expect(conditions.applying.isEmpty)
  }

  @Test("권한 바꾸기가 기기 꺼짐으로 실패하면 실패 줄을 보이고 기록하지 않으며 기기 목록을 다시 읽는다")
  func privacyNotBooted() async {
    let loaded = await Self.openedWithSample { $0.setPrivacyError(.deviceNotBooted) }
    await loaded.conditions.privacyTapped(.camera, .grant)
    #expect(loaded.conditions.draft?.message == .failed(.privacy(.camera), .deviceNotBooted))
    #expect(loaded.conditions.draft?.app.result == nil)
    #expect(loaded.conditions.privacyHistory.isEmpty)
    #expect(Self.fetchCount(loaded.simulator) == 2)
    #expect(loaded.conditions.applying.isEmpty)
  }

  @Test("권한 바꾸기가 기기 밖 이유로 실패하면 기기 목록을 다시 읽지 않고, 다음 적용이 실패 줄을 지운다")
  func privacyOtherFailure() async {
    let loaded = await Self.openedWithSample { $0.setPrivacyError(.commandFailed) }
    await loaded.conditions.privacyTapped(.camera, .grant)
    #expect(loaded.conditions.draft?.message == .failed(.privacy(.camera), .commandFailed))
    #expect(Self.fetchCount(loaded.simulator) == 1)

    loaded.simulator.setPrivacyError(nil)
    await loaded.conditions.privacyTapped(.camera, .grant)
    #expect(loaded.conditions.draft?.message == nil)
    #expect(loaded.conditions.draft?.app.result == .privacyChanged(.camera, .grant, appName: "Sample"))
  }

  // MARK: - 푸시

  @Test("입력 이벤트가 푸시 입력을 바꾸고, 폼의 빈 본문·JSON 공백뿐은 문제를 보이지 않고 보내기만 막는다")
  func pushInputs() async {
    let loaded = await Self.openedWithSample()
    let conditions = loaded.conditions
    #expect(conditions.draft?.app.pushInput == .form)
    #expect(conditions.draft?.app.pushPayload == nil)
    #expect(conditions.draft?.app.pushProblem == nil)

    conditions.pushTitleChanged("제목")
    conditions.pushBodyChanged("본문")
    #expect(conditions.draft?.app.pushTitle == "제목")
    #expect(conditions.draft?.app.pushPayload == (try? PushPayload.alert(title: "제목", body: "본문").get()))

    conditions.pushInputChanged(.json)
    #expect(conditions.draft?.app.pushInput == .json)
    // 처음 JSON 은 그대로 보낼 수 있는 예시다.
    #expect(conditions.draft?.app.pushPayload != nil)
    conditions.pushJSONChanged("  \n")
    #expect(conditions.draft?.app.pushPayload == nil)
    #expect(conditions.draft?.app.pushProblem == nil)
    conditions.pushJSONChanged("{\"aps\":")
    #expect(conditions.draft?.app.pushProblem == .notJSON)
    conditions.pushJSONChanged("{“aps”:{}}")
    #expect(conditions.draft?.app.pushProblem == .smartQuotes)
    conditions.pushJSONChanged("{\"aps\":{\"alert\":\"가\"}}")
    #expect(conditions.draft?.app.pushProblem == nil)
    // 한글은 UTF-8 3바이트로 센다.
    #expect(conditions.draft?.app.pushByteCount == 23)
  }

  @Test("JSON 모드로 보내면 입력 바이트 그대로 보내고, 보낸 뒤에도 입력은 그대로다")
  func pushSendsJSONBytes() async throws {
    let loaded = await Self.openedWithSample()
    let conditions = loaded.conditions
    let text = "{ \"aps\" : { \"alert\" : \"hi\" } }"
    conditions.pushInputChanged(.json)
    conditions.pushJSONChanged(text)
    await conditions.sendPushTapped()

    let payload = try? PushPayload.json(text).get()
    #expect(payload?.data == Data(text.utf8))
    #expect(try Self.pushCalls(loaded.simulator) == [.sendPush(#require(payload), Self.sample.bundleID, self.id)])
    #expect(conditions.draft?.app.result == .pushSent(appName: "Sample"))
    #expect(conditions.draft?.app.pushJSON == text)
  }

  @Test("보낼 내용이 없거나 앱을 고르지 않았으면 보내지 않는다")
  func pushGuards() async {
    let loaded = await Self.openedWithSample()
    let conditions = loaded.conditions
    await conditions.sendPushTapped()
    conditions.pushBodyChanged("본문")
    conditions.appSelected(nil)
    await conditions.sendPushTapped()
    #expect(Self.pushCalls(loaded.simulator).isEmpty)
  }

  @Test("푸시를 보내면 첫 await 전에 적용 중이 되고 연타는 무시되며, 보냄이면 성공 줄을 보인다")
  func pushSent() async {
    let loaded = await Self.openedWithSample()
    let conditions = loaded.conditions
    conditions.pushBodyChanged("본문")
    loaded.simulator.suspendConditions()
    let first = Self.start { await conditions.sendPushTapped() }
    await Self.waitUntil { !Self.pushCalls(loaded.simulator).isEmpty }
    #expect(conditions.applying[self.id] == .push)
    let second = Self.start { await conditions.sendPushTapped() }
    await Self.waitUntil { second.isFinished }

    loaded.simulator.resumeConditions()
    await first.value()
    #expect(Self.pushCalls(loaded.simulator).count == 1)
    #expect(conditions.applying.isEmpty)
    #expect(conditions.draft?.app.result == .pushSent(appName: "Sample"))
    #expect(conditions.draft?.app.pushBody == "본문")
  }

  @Test(
    "기기가 받지 않은 결과는 각 문구로 보인다",
    arguments: [
      (IOSPushOutcome.notAuthorized, TestConditionsMessage.pushNotAuthorized(appName: "Sample")),
      (.noVisibleContent, .pushNoVisibleContent),
      (.payloadRejected, .pushRejected),
    ]
  )
  func pushOutcomes(outcome: IOSPushOutcome, message: TestConditionsMessage) async {
    let loaded = await Self.openedWithSample { $0.setPushOutcome(outcome) }
    loaded.conditions.pushBodyChanged("본문")
    await loaded.conditions.sendPushTapped()
    #expect(loaded.conditions.draft?.message == message)
    #expect(loaded.conditions.draft?.app.result == nil)
    #expect(Self.fetchCount(loaded.simulator) == 1)
  }

  @Test("알림 권한 없음 문구의 앱 이름은 보내기를 시작한 때의 앱이다")
  func pushNotAuthorizedUsesStartApp() async {
    let loaded = await Self.openedWithSample { $0.setPushOutcome(.notAuthorized) }
    let conditions = loaded.conditions
    conditions.pushBodyChanged("본문")
    loaded.simulator.suspendConditions()
    let tap = Self.start { await conditions.sendPushTapped() }
    await Self.waitUntil { !Self.pushCalls(loaded.simulator).isEmpty }
    conditions.appSelected(Self.rig.bundleID)
    loaded.simulator.resumeConditions()
    await tap.value()
    #expect(conditions.draft?.message == .pushNotAuthorized(appName: "Sample"))
  }

  @Test("푸시가 기기 꺼짐으로 실패하면 실패 줄을 보이고 기기 목록을 다시 읽으며, 기기 밖 이유면 다시 읽지 않는다")
  func pushFailures() async {
    let loaded = await Self.openedWithSample { $0.setPushError(.deviceNotBooted) }
    loaded.conditions.pushBodyChanged("본문")
    await loaded.conditions.sendPushTapped()
    #expect(loaded.conditions.draft?.message == .failed(.push, .deviceNotBooted))
    #expect(Self.fetchCount(loaded.simulator) == 2)

    loaded.simulator.setPushError(.developerToolsUnavailable)
    await loaded.conditions.sendPushTapped()
    #expect(loaded.conditions.draft?.message == .failed(.push, .developerToolsUnavailable))
    #expect(Self.fetchCount(loaded.simulator) == 2)
  }

  @Test("시트를 닫은 뒤 끝난 푸시는 보이는 것이 없고 적용 중만 풀린다")
  func pushAfterClose() async {
    let loaded = await Self.openedWithSample()
    let conditions = loaded.conditions
    conditions.pushBodyChanged("본문")
    loaded.simulator.suspendConditions()
    let tap = Self.start { await conditions.sendPushTapped() }
    await Self.waitUntil { !Self.pushCalls(loaded.simulator).isEmpty }
    conditions.closeTapped()
    loaded.simulator.resumeConditions()
    await tap.value()
    #expect(conditions.draft == nil)
    #expect(conditions.applying.isEmpty)
  }

  @Test("다음 적용을 시작하면 지난 성공 줄을 지운다")
  func nextApplyClearsResult() async {
    let loaded = await Self.openedWithSample()
    let conditions = loaded.conditions
    await conditions.privacyTapped(.camera, .grant)
    #expect(conditions.draft?.app.result != nil)
    await conditions.appearanceSelected(.dark)
    #expect(conditions.draft?.app.result == nil)
  }
}
