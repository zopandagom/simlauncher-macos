import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing

/// Fake 의 앱 단위 테스트 조건(privacy·push): 호출 기록·기기 상태 검사(install 과 같은 순서)·설정한 결과·에러·멈춤.
struct SimulatorClientFakeAppConditionsTests {
  private static let app = AppBundleID("com.example.app")!

  private static func fake() -> SimulatorClientFake {
    SimulatorClientFake(inventory: .sample)
  }

  private static func payload() throws -> PushPayload {
    try PushPayload.alert(title: "", body: "hi").get()
  }

  @Test("기본: privacy 는 성공, push 는 sent 이고 호출을 기록한다")
  func defaults() async throws {
    let fake = Self.fake()
    let id = SampleID.iPhoneOn
    let payload = try Self.payload()

    try await fake.setPrivacy(.grant, .camera, for: Self.app, on: id)
    #expect(try await fake.sendPush(payload, to: Self.app, on: id) == .sent)
    #expect(fake.calls == [
      .testCondition(.setPrivacy(.grant, .camera, Self.app, id)),
      .testCondition(.sendPush(payload, Self.app, id)),
    ])
  }

  @Test("목록에 없으면 deviceNotFound, 켜져 있지 않으면 deviceNotBooted (두 호출 모두)")
  func deviceState() async throws {
    let fake = Self.fake()
    let payload = try Self.payload()
    let missing = VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF")

    for (id, expected) in [(SampleID.iPhoneOff, SimulatorError.deviceNotBooted), (missing, .deviceNotFound)] {
      await #expect(throws: expected) { try await fake.setPrivacy(.reset, .photos, for: Self.app, on: id) }
      await #expect(throws: expected) { try await fake.sendPush(payload, to: Self.app, on: id) }
    }
  }

  @Test("설정한 결과·에러: 에러가 결과보다 먼저다")
  func configured() async throws {
    let fake = Self.fake()
    let id = SampleID.iPhoneOn
    let payload = try Self.payload()

    fake.setPushOutcome(.notAuthorized)
    #expect(try await fake.sendPush(payload, to: Self.app, on: id) == .notAuthorized)
    fake.setPushError(.commandFailed)
    await #expect(throws: SimulatorError.commandFailed) { try await fake.sendPush(payload, to: Self.app, on: id) }
    fake.setPushError(nil)
    #expect(try await fake.sendPush(payload, to: Self.app, on: id) == .notAuthorized)

    fake.setPrivacyError(.deviceNotBooted)
    await #expect(throws: SimulatorError.deviceNotBooted) {
      try await fake.setPrivacy(.revoke, .microphone, for: Self.app, on: id)
    }
    fake.setPrivacyError(nil)
    try await fake.setPrivacy(.revoke, .microphone, for: Self.app, on: id)
  }

  @Test("suspendConditions 는 두 호출을 멈추고, suspendConditionReads 는 멈추지 않는다")
  func suspend() async throws {
    let fake = Self.fake()
    let id = SampleID.iPhoneOn
    let payload = try Self.payload()

    fake.suspendConditionReads()
    try await fake.setPrivacy(.grant, .location, for: Self.app, on: id)
    #expect(try await fake.sendPush(payload, to: Self.app, on: id) == .sent)
    fake.resumeConditionReads()

    fake.suspendConditions()
    let push = Task { try await fake.sendPush(payload, to: Self.app, on: id) }
    let privacy = Task { try await fake.setPrivacy(.grant, .contacts, for: Self.app, on: id) }
    while fake.calls.count < 4 {
      await Task.yield()
    }
    fake.resumeConditions()
    #expect(try await push.value == .sent)
    try await privacy.value
  }
}
