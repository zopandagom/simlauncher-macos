import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing

struct SimulatorClientFakeInstallTests {
  private static let app = URL(filePath: "/tmp/Sample.app", directoryHint: .isDirectory)
  private static let bundleID = AppBundleID("com.example.sample")!

  @Test("켜진 기기에 설치하면 기록하고 목록은 바꾸지 않는다")
  func installOnBootedDevice() async throws {
    let fake = SimulatorClientFake(inventory: .sample)

    try await fake.install(Self.app, on: SampleID.iPhoneOn)

    #expect(fake.calls == [.install(Self.app, SampleID.iPhoneOn)])
    #expect(try await fake.fetchInventory() == .sample)
  }

  @Test("꺼진 기기는 deviceNotBooted, 목록에 없는 기기는 deviceNotFound")
  func installChecksDeviceState() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    let missing = VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF")

    await #expect(throws: SimulatorError.deviceNotBooted) { try await fake.install(Self.app, on: SampleID.iPhoneOff) }
    await #expect(throws: SimulatorError.deviceNotFound) { try await fake.install(Self.app, on: missing) }
    #expect(fake.calls == [.install(Self.app, SampleID.iPhoneOff), .install(Self.app, missing)])
  }

  @Test("켠 뒤에는 설치되고, 설정한 에러는 상태보다 먼저 던진다")
  func installAfterBootAndConfiguredError() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    try await fake.boot(SampleID.iPhoneOff)
    try await fake.install(Self.app, on: SampleID.iPhoneOff)

    fake.setInstallError(.appIncompatible)
    await #expect(throws: SimulatorError.appIncompatible) { try await fake.install(Self.app, on: SampleID.iPhoneOn) }
    fake.setInstallError(nil)
    try await fake.install(Self.app, on: SampleID.iPhoneOn)
  }

  @Test("멈춘 install 은 기록된 뒤 resume 까지 기다리고, 깨어난 뒤의 설정을 쓴다")
  func suspendInstalls() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.suspendInstalls()
    let task = Task { try await fake.install(Self.app, on: SampleID.iPhoneOn) }
    while !fake.calls.contains(.install(Self.app, SampleID.iPhoneOn)) {
      await Task.yield()
    }

    fake.setInstallError(.appRequiresNewerOS)
    fake.resumeInstalls()

    await #expect(throws: SimulatorError.appRequiresNewerOS) { try await task.value }
    fake.setInstallError(nil)
    try await fake.install(Self.app, on: SampleID.iPhoneOn)
  }

  @Test("launch 는 설치 여부와 상관없이 기록하고 성공하며, 설정한 에러를 던진다")
  func launch() async throws {
    let fake = SimulatorClientFake(inventory: .sample)

    try await fake.launch(Self.bundleID, on: SampleID.iPhoneOff)
    fake.setLaunchError(.appLaunchFailed)
    await #expect(throws: SimulatorError.appLaunchFailed) { try await fake.launch(Self.bundleID, on: SampleID.iPhoneOn)
    }

    #expect(fake.calls == [.launch(Self.bundleID, SampleID.iPhoneOff), .launch(Self.bundleID, SampleID.iPhoneOn)])
  }
}
