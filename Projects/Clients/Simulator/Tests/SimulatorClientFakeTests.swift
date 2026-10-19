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
    #expect(DeviceList(inventory: .noCreatableDeviceType).emptyReason == .noCreatableDeviceType)
    #expect(DeviceCreationOptions(inventory: .noCreatableDeviceType).isEmpty)
    let list = DeviceList(inventory: .sample)
    #expect(list.sections.map(\.runtime.name) == ["iOS 27.0", "iOS 26.0", "iOS 25.0"])
    #expect(list.device(id: SampleID.watch) == nil)
  }

  @Test("create 는 꺼진·쓸 수 있는 기기를 끝에 더하고 정해진 UDID 를 돌려준다")
  func createAppendsDevice() async throws {
    let fake = SimulatorClientFake(inventory: .sample)

    let first = try await fake.create(
      name: "새 iPad",
      deviceType: SampleDeviceType.iPadA16.id,
      runtime: SampleRuntime.iOS26.id
    )
    let second = try await fake.create(
      name: "새 iPhone",
      deviceType: SampleDeviceType.iPhone17.id,
      runtime: SampleRuntime.iOS27.id
    )
    let inventory = try await fake.fetchInventory()

    #expect(first == VirtualDevice.ID("00000000-0000-0000-0001-000000000001"))
    #expect(second == VirtualDevice.ID("00000000-0000-0000-0001-000000000002"))
    #expect(inventory.devices.suffix(2) == [
      VirtualDevice(
        id: first,
        name: "새 iPad",
        family: .tablet,
        state: .shutdown,
        availability: .available,
        runtime: SampleRuntime.iOS26
      ),
      VirtualDevice(
        id: second,
        name: "새 iPhone",
        family: .phone,
        state: .shutdown,
        availability: .available,
        runtime: SampleRuntime.iOS27
      ),
    ])
    #expect(fake.calls.first == .create(
      name: "새 iPad",
      deviceType: SampleDeviceType.iPadA16.id,
      runtime: SampleRuntime.iOS26.id
    ))
  }

  @Test("목록에 없는 런타임·기기 종류로 create 하면 creationOptionUnavailable 이고 목록은 그대로다")
  func createUnknownOption() async throws {
    let fake = SimulatorClientFake(inventory: .sample)

    await #expect(throws: SimulatorError.creationOptionUnavailable) {
      try await fake.create(name: "A", deviceType: SampleDeviceType.iPhone17.id, runtime: DeviceRuntime.ID("nope"))
    }
    await #expect(throws: SimulatorError.creationOptionUnavailable) {
      try await fake.create(name: "A", deviceType: DeviceType.ID("nope"), runtime: SampleRuntime.iOS27.id)
    }
    #expect(try await fake.fetchInventory() == .sample)
  }

  @Test("delete 는 목록에서 빼고(없는 기기도 성공), erase 는 목록을 바꾸지 않는다")
  func deleteAndErase() async throws {
    let fake = SimulatorClientFake(inventory: .sample)

    try await fake.erase(SampleID.iPadOff)
    #expect(try await fake.fetchInventory() == .sample)

    try await fake.delete(SampleID.iPadOff)
    try await fake.delete(VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF"))
    let inventory = try await fake.fetchInventory()

    #expect(inventory.devices.map(\.id) == DeviceInventory.sample.devices.map(\.id).filter { $0 != SampleID.iPadOff })
    #expect(fake.calls == [
      .erase(SampleID.iPadOff),
      .fetchInventory,
      .delete(SampleID.iPadOff),
      .delete(VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF")),
      .fetchInventory,
    ])
  }

  @Test("create·delete·erase 에 설정한 에러를 던지고 목록을 바꾸지 않는다")
  func mutationErrors() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.setCreateError(.invalidDeviceName)
    fake.setDeleteError(.deviceNotShutdown)
    fake.setEraseError(.commandFailed)

    await #expect(throws: SimulatorError.invalidDeviceName) {
      try await fake.create(name: "A", deviceType: SampleDeviceType.iPhone17.id, runtime: SampleRuntime.iOS27.id)
    }
    await #expect(throws: SimulatorError.deviceNotShutdown) { try await fake.delete(SampleID.iPadOff) }
    await #expect(throws: SimulatorError.commandFailed) { try await fake.erase(SampleID.iPadOff) }
    #expect(try await fake.fetchInventory() == .sample)
  }

  @Test("멈춘 create 는 기록된 뒤 resume 까지 기다린다")
  func suspendCreates() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.suspendCreates()
    let call = SimulatorClientFake.Call.create(
      name: "A",
      deviceType: SampleDeviceType.iPhone17.id,
      runtime: SampleRuntime.iOS27.id
    )
    let task = Task {
      try await fake.create(name: "A", deviceType: SampleDeviceType.iPhone17.id, runtime: SampleRuntime.iOS27.id)
    }
    while !fake.calls.contains(call) {
      await Task.yield()
    }
    #expect(try await fake.fetchInventory() == .sample)

    fake.resumeCreates()

    let id = try await task.value
    #expect(try await fake.fetchInventory().devices.last?.id == id)
  }

  @Test("멈춘 delete 는 기록된 뒤 resume 까지 기다린다")
  func suspendDeletes() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.suspendDeletes()
    let task = Task { try await fake.delete(SampleID.iPadOff) }
    while !fake.calls.contains(.delete(SampleID.iPadOff)) {
      await Task.yield()
    }
    #expect(try await fake.fetchInventory() == .sample)

    fake.resumeDeletes()

    try await task.value
    #expect(try await fake.fetchInventory().devices.contains { $0.id == SampleID.iPadOff } == false)
  }

  @Test("멈춘 erase 는 기록된 뒤 resume 까지 기다리고, 깨어난 뒤의 설정을 쓴다")
  func suspendErases() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.suspendErases()
    let task = Task { try await fake.erase(SampleID.iPadOff) }
    while !fake.calls.contains(.erase(SampleID.iPadOff)) {
      await Task.yield()
    }
    fake.setEraseError(.commandFailed)
    fake.resumeErases()

    await #expect(throws: SimulatorError.commandFailed) { try await task.value }
  }

  @Test("boot·shutdown·create·delete·erase 뒤에도 런타임·기기 종류가 그대로다")
  func mutationsKeepRuntimesAndDeviceTypes() async throws {
    let fake = SimulatorClientFake(inventory: .sample)

    try await fake.boot(SampleID.iPhoneOff)
    try await fake.shutdown(SampleID.iPhoneOn)
    _ = try await fake.create(name: "A", deviceType: SampleDeviceType.iPhone17.id, runtime: SampleRuntime.iOS27.id)
    try await fake.delete(SampleID.iPadOff)
    try await fake.erase(SampleID.iPhoneIOS26)
    let inventory = try await fake.fetchInventory()

    #expect(inventory.runtimes == DeviceInventory.sample.runtimes)
    #expect(inventory.deviceTypes == DeviceInventory.sample.deviceTypes)
    #expect(DeviceCreationOptions(inventory: inventory) == DeviceCreationOptions(inventory: .sample))
  }

  @Test("샘플 목록의 생성 선택지")
  func sampleCreationOptions() {
    let options = DeviceCreationOptions(inventory: .sample)
    #expect(options.runtimes == [SampleRuntime.iOS27, SampleRuntime.iOS26])
    #expect(options.deviceTypes(for: SampleRuntime.iOS27.id) == [
      SampleDeviceType.iPhone17Pro,
      SampleDeviceType.iPhone17,
      SampleDeviceType.iPadA16,
    ])
    #expect(DeviceCreationOptions(inventory: .noDevices).runtimes == [SampleRuntime.iOS27])
    #expect(DeviceCreationOptions(inventory: .noRuntime).isEmpty)
  }
}
