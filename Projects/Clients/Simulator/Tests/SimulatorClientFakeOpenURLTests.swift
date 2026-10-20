import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing

struct SimulatorClientFakeOpenURLTests {
  private static let link = DeepLink("myapp://item/1")!

  @Test("켜진 기기에서 열면 기록하고 목록은 바꾸지 않는다")
  func openOnBootedDevice() async throws {
    let fake = SimulatorClientFake(inventory: .sample)

    try await fake.openURL(Self.link, on: SampleID.iPhoneOn)

    #expect(fake.calls == [.openURL(Self.link, SampleID.iPhoneOn)])
    #expect(try await fake.fetchInventory() == .sample)
  }

  @Test("꺼진 기기는 deviceNotBooted, 목록에 없는 기기는 deviceNotFound")
  func checksDeviceState() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    let missing = VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF")

    await #expect(throws: SimulatorError.deviceNotBooted) { try await fake.openURL(Self.link, on: SampleID.iPhoneOff) }
    await #expect(throws: SimulatorError.deviceNotFound) { try await fake.openURL(Self.link, on: missing) }
    #expect(fake.calls == [.openURL(Self.link, SampleID.iPhoneOff), .openURL(Self.link, missing)])
  }

  @Test("켠 뒤에는 열리고, 설정한 에러는 상태보다 먼저 던진다")
  func openAfterBootAndConfiguredError() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    try await fake.boot(SampleID.iPhoneOff)
    try await fake.openURL(Self.link, on: SampleID.iPhoneOff)

    fake.setOpenURLError(.urlNotHandled)
    await #expect(throws: SimulatorError.urlNotHandled) { try await fake.openURL(Self.link, on: SampleID.iPhoneOn) }
    let missing = VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF")
    await #expect(throws: SimulatorError.urlNotHandled) { try await fake.openURL(Self.link, on: missing) }
    fake.setOpenURLError(nil)
    try await fake.openURL(Self.link, on: SampleID.iPhoneOn)
  }

  @Test("멈춘 openURL 은 기록된 뒤 resume 까지 기다리고, 깨어난 뒤의 설정을 쓴다")
  func suspendOpenURLs() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.suspendOpenURLs()
    let task = Task { try await fake.openURL(Self.link, on: SampleID.iPhoneOn) }
    while !fake.calls.contains(.openURL(Self.link, SampleID.iPhoneOn)) {
      await Task.yield()
    }

    fake.setOpenURLError(.invalidURL)
    fake.resumeOpenURLs()

    await #expect(throws: SimulatorError.invalidURL) { try await task.value }
    fake.setOpenURLError(nil)
    try await fake.openURL(Self.link, on: SampleID.iPhoneOn)
  }
}
