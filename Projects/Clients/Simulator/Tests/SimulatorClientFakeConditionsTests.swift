import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing

/// Fake 의 테스트 조건: 기기 상태 검사(install 과 같은 순서)·지금 값 바꾸기·설정한 결과·멈춤.
struct SimulatorClientFakeConditionsTests {
  private static func fake() -> SimulatorClientFake {
    SimulatorClientFake(inventory: .sample)
  }

  @Test("기본 값은 라이트·large·고대비 끔이고, 성공한 쓰기가 그 항목만 바꾸며 호출을 기록한다")
  func readWrite() async throws {
    let fake = Self.fake()
    let id = SampleID.iPhoneOn

    #expect(try await fake.displaySettings(on: id) == SimulatorClientFake.defaultDisplaySettings)
    #expect(try await fake.setDisplaySetting(.appearance(.dark), on: id) == .applied)
    #expect(try await fake.displaySettings(on: id).appearance == .value(.dark))
    #expect(fake.displaySettings(for: id).contentSize == .value(.large))
    #expect(fake.calls == [
      .testCondition(.displaySettings(id)),
      .testCondition(.setDisplaySetting(.appearance(.dark), id)),
      .testCondition(.displaySettings(id)),
    ])
  }

  @Test("목록에 없으면 deviceNotFound, 켜져 있지 않으면 deviceNotBooted (세 호출 모두)")
  func deviceState() async throws {
    let fake = Self.fake()
    let off = SampleID.iPhoneOff
    let missing = VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF")

    for (id, expected) in [(off, SimulatorError.deviceNotBooted), (missing, .deviceNotFound)] {
      await #expect(throws: expected) { try await fake.displaySettings(on: id) }
      await #expect(throws: expected) { try await fake.setDisplaySetting(.increaseContrast(true), on: id) }
      await #expect(throws: expected) { try await fake.simulateLocation(.clear, on: id) }
    }
  }

  @Test("설정한 에러·notApplied·시나리오 없음")
  func configured() async throws {
    let fake = Self.fake()
    let id = SampleID.iPhoneOn
    let read = IOSDisplaySettings(
      appearance: .value(.light),
      contentSize: .unsupported,
      increaseContrast: .value(false)
    )

    fake.setDisplaySettingsError(.commandFailed)
    await #expect(throws: SimulatorError.commandFailed) { try await fake.displaySettings(on: id) }
    fake.setDisplaySettingsError(nil)

    fake.setDisplaySettingNotApplied(read)
    #expect(try await fake.setDisplaySetting(.contentSize(.small), on: id) == .notApplied(read))
    #expect(fake.displaySettings(for: id) == read)
    fake.setDisplaySettingNotApplied(nil)

    fake.setDisplaySettingError(.deviceNotBooted)
    await #expect(throws: SimulatorError.deviceNotBooted) {
      try await fake.setDisplaySetting(.appearance(.dark), on: id)
    }
    #expect(fake.displaySettings(for: id).appearance == .value(.light))

    fake.setScenarioUnavailable(true)
    #expect(try await fake.simulateLocation(.scenario(.apple), on: id) == .scenarioUnavailable)
    #expect(try await fake.simulateLocation(.clear, on: id) == .applied)
    fake.setLocationError(.commandFailed)
    await #expect(throws: SimulatorError.commandFailed) { try await fake.simulateLocation(.clear, on: id) }
  }

  @Test("멈춘 호출은 기록만 하고 resumeConditions 까지 기다린다")
  func suspend() async throws {
    let fake = Self.fake()
    let id = SampleID.iPhoneOn
    fake.suspendConditions()

    let task = Task { try await fake.simulateLocation(.clear, on: id) }
    while fake.calls.isEmpty {
      await Task.yield()
    }
    #expect(fake.calls == [.testCondition(.simulateLocation(.clear, id))])
    fake.resumeConditions()
    #expect(try await task.value == .applied)
  }

  @Test("읽기만 멈추면 쓰기는 그대로 돌아오고, 읽기는 resumeConditionReads 뒤 쓴 값을 돌려준다")
  func suspendReadsOnly() async throws {
    let fake = Self.fake()
    let id = SampleID.iPhoneOn
    fake.suspendConditionReads()

    let read = Task { try await fake.displaySettings(on: id) }
    while fake.calls.isEmpty {
      await Task.yield()
    }
    #expect(try await fake.setDisplaySetting(.appearance(.dark), on: id) == .applied)
    fake.resumeConditionReads()
    #expect(try await read.value.appearance == .value(.dark))
  }
}
