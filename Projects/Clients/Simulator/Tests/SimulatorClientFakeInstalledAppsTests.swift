import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing

struct SimulatorClientFakeInstalledAppsTests {
  private static let app = InstalledApp(
    bundleID: AppBundleID("com.example.app")!,
    displayName: "App",
    version: "1.0",
    build: "1"
  )

  @Test("켜진 기기는 설정한 목록을 그대로, 설정하지 않으면 빈 목록을 돌려주고 호출을 기록한다")
  func listOnBootedDevice() async throws {
    let fake = SimulatorClientFake(inventory: .sample)

    #expect(try await fake.installedApps(on: SampleID.iPhoneOn).isEmpty)
    fake.setInstalledApps([Self.app], on: SampleID.iPhoneOn)
    #expect(try await fake.installedApps(on: SampleID.iPhoneOn) == [Self.app])

    #expect(fake.calls == [.installedApps(SampleID.iPhoneOn), .installedApps(SampleID.iPhoneOn)])
    #expect(try await fake.fetchInventory() == .sample)
  }

  @Test("꺼진 기기는 deviceNotBooted, 목록에 없는 기기는 deviceNotFound")
  func checksDeviceState() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.setInstalledApps([Self.app], on: SampleID.iPhoneOff)
    let missing = VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF")

    await #expect(throws: SimulatorError.deviceNotBooted) { try await fake.installedApps(on: SampleID.iPhoneOff) }
    await #expect(throws: SimulatorError.deviceNotFound) { try await fake.installedApps(on: missing) }
    #expect(fake.calls == [.installedApps(SampleID.iPhoneOff), .installedApps(missing)])
  }

  @Test("켠 뒤에는 읽히고, 설정한 에러는 상태보다 먼저 던진다")
  func listAfterBootAndConfiguredError() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.setInstalledApps([Self.app], on: SampleID.iPhoneOff)
    try await fake.boot(SampleID.iPhoneOff)
    #expect(try await fake.installedApps(on: SampleID.iPhoneOff) == [Self.app])

    fake.setInstalledAppsError(.unexpectedOutput)
    await #expect(throws: SimulatorError.unexpectedOutput) { try await fake.installedApps(on: SampleID.iPhoneOn) }
    let missing = VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF")
    await #expect(throws: SimulatorError.unexpectedOutput) { try await fake.installedApps(on: missing) }
    fake.setInstalledAppsError(nil)
    #expect(try await fake.installedApps(on: SampleID.iPhoneOff) == [Self.app])
  }

  @Test("멈춘 installedApps 는 기록된 뒤 resume 까지 기다리고, 깨어난 뒤의 설정을 쓴다")
  func suspendInstalledApps() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.suspendInstalledApps()
    let task = Task { try await fake.installedApps(on: SampleID.iPhoneOn) }
    while !fake.calls.contains(.installedApps(SampleID.iPhoneOn)) {
      await Task.yield()
    }

    fake.setInstalledApps([Self.app], on: SampleID.iPhoneOn)
    fake.resumeInstalledApps()

    #expect(try await task.value == [Self.app])
    fake.setInstalledAppsError(.deviceNotFound)
    await #expect(throws: SimulatorError.deviceNotFound) { try await fake.installedApps(on: SampleID.iPhoneOn) }
  }
}
