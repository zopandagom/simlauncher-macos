import Core
import SimulatorInterface
import SimulatorTesting
import Testing

struct SimulatorClientFakeTests {
  @Test("호출을 순서대로 기록하고 boot·shutdown 결과를 목록에 남긴다")
  func recordsCallsAndUpdatesState() async throws {
    let fake = SimulatorClientFake(inventory: .sample)

    try await fake.boot(SampleID.iPhoneOff)
    try await fake.shutdown(SampleID.iPhoneOn)
    try await fake.openSimulatorApp()
    let inventory = try await fake.fetchInventory()

    #expect(fake.calls == [.boot(SampleID.iPhoneOff), .shutdown(SampleID.iPhoneOn), .openSimulatorApp, .fetchInventory])
    #expect(inventory.devices.first { $0.id == SampleID.iPhoneOff }?.state == .booted)
    #expect(inventory.devices.first { $0.id == SampleID.iPhoneOn }?.state == .shutdown)
  }

  @Test("설정한 에러를 던지고, 실패한 boot 는 목록을 바꾸지 않는다")
  func throwsConfiguredErrors() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.setFetchError(.unexpectedOutput)
    fake.setBootError(.deviceNotFound)
    fake.setShutdownError(.commandFailed)
    fake.setOpenAppError(.simulatorAppNotFound)

    await #expect(throws: SimulatorError.unexpectedOutput) { try await fake.fetchInventory() }
    await #expect(throws: SimulatorError.deviceNotFound) { try await fake.boot(SampleID.iPhoneOff) }
    await #expect(throws: SimulatorError.commandFailed) { try await fake.shutdown(SampleID.iPhoneOn) }
    await #expect(throws: SimulatorError.simulatorAppNotFound) { try await fake.openSimulatorApp() }

    fake.setFetchError(nil)
    let inventory = try await fake.fetchInventory()
    #expect(inventory == .sample)
  }

  @Test("멈춘 boot 은 기록된 뒤 resume 까지 기다리고, 깨어난 뒤의 설정을 쓴다")
  func suspendBoots() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.suspendBoots()
    let task = Task { try await fake.boot(SampleID.iPhoneOff) }
    while !fake.calls.contains(.boot(SampleID.iPhoneOff)) {
      await Task.yield()
    }
    #expect(try await fake.fetchInventory().devices.first { $0.id == SampleID.iPhoneOff }?.state == .shutdown)

    fake.setBootError(.commandFailed)
    fake.resumeBoots()

    await #expect(throws: SimulatorError.commandFailed) { try await task.value }
    fake.setBootError(nil)
    try await fake.boot(SampleID.iPadOff)
  }

  @Test("멈춘 fetch 는 resume 까지 기다리고, resume 뒤의 호출은 기다리지 않는다")
  func suspendFetches() async throws {
    let fake = SimulatorClientFake(inventory: .noDevices)
    fake.suspendFetches()
    let task = Task { try await fake.fetchInventory() }
    while !fake.calls.contains(.fetchInventory) {
      await Task.yield()
    }
    fake.setInventory(.sample)
    fake.resumeFetches()

    #expect(try await task.value == .sample)
    #expect(try await fake.fetchInventory() == .sample)
  }

  @Test("샘플 목록의 빈 이유")
  func samples() {
    #expect(DeviceList(inventory: .noRuntime).emptyReason == .noIOSRuntime)
    #expect(DeviceList(inventory: .noDevices).emptyReason == .noDevices)
    let list = DeviceList(inventory: .sample)
    #expect(list.sections.map(\.runtime.name) == ["iOS 27.0", "iOS 26.0", "iOS 25.0"])
    #expect(list.device(id: SampleID.watch) == nil)
  }
}
