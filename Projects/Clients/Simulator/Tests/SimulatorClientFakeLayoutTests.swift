import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing

struct SimulatorClientFakeLayoutTests {
  private static let missing = VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF")
  private static let app = AppBundleID("com.example.app")!
  private static let runner = AppBundleID(IOSLayoutRunner.appBundleID)!

  @Test("실행 중 앱 목록은 기기별로 설정한 값(기본 빈 목록)을 그대로 돌려주고 기록한다")
  func runningApplications() async throws {
    let fake = SimulatorClientFake(inventory: .sample)

    #expect(try await fake.runningApplications(on: SampleID.iPhoneOn).isEmpty)
    fake.setRunningApplications([Self.runner, Self.app], for: SampleID.iPhoneOn)

    #expect(try await fake.runningApplications(on: SampleID.iPhoneOn) == [Self.runner, Self.app])
    #expect(fake.calls == [.runningApplications(SampleID.iPhoneOn), .runningApplications(SampleID.iPhoneOn)])
  }

  @Test("꺼진 기기는 deviceNotBooted, 목록에 없는 기기는 deviceNotFound, 설정한 에러는 상태보다 먼저")
  func checksDeviceState() async throws {
    let fake = SimulatorClientFake(inventory: .sample)

    await #expect(throws: SimulatorError.deviceNotBooted) { try await fake.runningApplications(on: SampleID.iPhoneOff) }
    await #expect(throws: SimulatorError.deviceNotFound) { try await fake.runningApplications(on: Self.missing) }
    await #expect(throws: SimulatorError.deviceNotBooted) { try await fake.uninstall(Self.app, on: SampleID.iPhoneOff) }
    await #expect(throws: SimulatorError.deviceNotFound) { try await fake.uninstall(Self.app, on: Self.missing) }

    fake.setRunningApplicationsError(.unexpectedOutput)
    fake.setUninstallError(.commandFailed)
    await #expect(throws: SimulatorError.unexpectedOutput) { try await fake.runningApplications(on: SampleID.iPhoneOn) }
    await #expect(throws: SimulatorError.commandFailed) { try await fake.uninstall(Self.app, on: SampleID.iPhoneOn) }
  }

  @Test("uninstall 은 기록하고 목록·설치된 앱은 바꾸지 않는다")
  func uninstallRecords() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.setRunningApplications([Self.runner], for: SampleID.iPhoneOn)

    try await fake.uninstall(Self.runner, on: SampleID.iPhoneOn)

    #expect(fake.calls == [.uninstall(Self.runner, SampleID.iPhoneOn)])
    #expect(try await fake.runningApplications(on: SampleID.iPhoneOn) == [Self.runner])
    #expect(try await fake.fetchInventory() == .sample)
  }

  @Test("멈춘 uninstall 은 기록된 뒤 resume 까지 기다린다")
  func suspendUninstalls() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.suspendUninstalls()
    let task = Task { try await fake.uninstall(Self.runner, on: SampleID.iPhoneOn) }
    while !fake.calls.contains(.uninstall(Self.runner, SampleID.iPhoneOn)) {
      await Task.yield()
    }

    fake.setUninstallError(.deviceNotBooted)
    fake.resumeUninstalls()

    await #expect(throws: SimulatorError.deviceNotBooted) { try await task.value }
    fake.setUninstallError(nil)
    try await fake.uninstall(Self.runner, on: SampleID.iPhoneOn)
  }

  @Test("멈춘 runningApplications 는 기록된 뒤 resume 까지 기다린다")
  func suspendRunningApplications() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.suspendRunningApplications()
    let task = Task { try await fake.runningApplications(on: SampleID.iPhoneOn) }
    while !fake.calls.contains(.runningApplications(SampleID.iPhoneOn)) {
      await Task.yield()
    }

    fake.setRunningApplications([Self.app], for: SampleID.iPhoneOn)
    fake.resumeRunningApplications()

    #expect(try await task.value == [Self.app])
  }
}
