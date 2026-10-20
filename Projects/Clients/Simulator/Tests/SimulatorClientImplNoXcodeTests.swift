import CommandInterface
import CommandTesting
import Core
import Foundation
import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// provider 가 nil 을 돌려주면(쓸 Xcode 없음) 어떤 명령도 실행하지 않는다.
/// 개발자 도구가 없는 Mac 에서 `/usr/bin/xcrun` 같은 shim 을 실행하면 Command Line Tools 설치 대화상자가 뜰 수 있다.
struct SimulatorClientImplNoXcodeTests {
  enum Operation: String, CaseIterable, Sendable {
    case fetchInventory, boot, shutdown, create, delete, erase, openSimulatorApp, install, launch, openURL
  }

  private static let udid = VirtualDevice.ID("B66201ED-154C-4F97-A6C7-C88F42E8D3A7")
  private static let developer = URL(filePath: "/X/Xcode.app/Contents/Developer", directoryHint: .isDirectory)

  @Test("provider 가 nil 을 돌려주면 명령 없이 developerToolsUnavailable 이고, provider 는 한 번이다", arguments: Operation.allCases)
  func providerReturnsNil(operation: Operation) async throws {
    let command = CommandClientFake { _ in .success() }
    let counter = ProviderCounter(returning: nil)

    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.perform(operation, on: Self.client(command, provider: counter))
    }
    #expect(command.invocations.isEmpty)
    #expect(counter.calls == 1)
  }

  @Test("boot·shutdown 도 UDID 형식이 아니면 provider 를 부르지 않는다", arguments: [Operation.boot, .shutdown])
  func invalidUDIDBeforeProvider(operation: Operation) async {
    let command = CommandClientFake { _ in .success() }
    let counter = ProviderCounter(returning: Self.developer)
    let client = Self.client(command, provider: counter)

    await #expect(throws: SimulatorError.deviceNotFound) {
      switch operation {
      case .boot: try await client.boot(VirtualDevice.ID("-h"))
      default: try await client.shutdown(VirtualDevice.ID("-h"))
      }
    }
    #expect(command.invocations.isEmpty)
    #expect(counter.calls == 0)
  }

  private static func client(_ command: CommandClientFake, provider: ProviderCounter) -> SimulatorClientImpl {
    SimulatorClientImpl(
      developerDirectory: { provider.provide() },
      command: command,
      fileExists: { _ in true },
      baseEnvironment: ["DEVELOPER_DIR": "/old"]
    )
  }

  private static func perform(_ operation: Operation, on client: SimulatorClientImpl) async throws(SimulatorError) {
    switch operation {
    case .fetchInventory:
      _ = try await client.fetchInventory()
    case .boot:
      try await client.boot(self.udid)
    case .shutdown:
      try await client.shutdown(self.udid)
    case .create:
      _ = try await client.create(
        name: "iPhone",
        deviceType: DeviceType.ID("com.apple.CoreSimulator.SimDeviceType.iPhone-17"),
        runtime: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-27-0")
      )
    case .delete:
      try await client.delete(self.udid)
    case .erase:
      try await client.erase(self.udid)
    case .openSimulatorApp:
      try await client.openSimulatorApp()
    case .install:
      try await client.install(URL(filePath: "/tmp/A.app", directoryHint: .isDirectory), on: self.udid)
    case .launch:
      try await client.launch(AppBundleID("com.example.ok")!, on: self.udid)
    case .openURL:
      try await client.openURL(DeepLink("https://example.com")!, on: self.udid)
    }
  }
}
