import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing

struct SimulatorClientFakeScreenshotTests {
  private static let file = URL(filePath: "/SimLauncher-Fake/a.png")
  private static let missing = VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF")

  @Test("켜진 기기는 기록하고 목록은 바꾸지 않는다")
  func screenshotOnBootedDevice() async throws {
    let fake = SimulatorClientFake(inventory: .sample)

    try await fake.screenshot(on: SampleID.iPhoneOn, to: Self.file)

    #expect(fake.calls == [.screenshot(SampleID.iPhoneOn, Self.file)])
    #expect(try await fake.fetchInventory() == .sample)
  }

  @Test("꺼진 기기는 deviceNotBooted, 목록에 없는 기기는 deviceNotFound")
  func checksDeviceState() async throws {
    let fake = SimulatorClientFake(inventory: .sample)

    await #expect(throws: SimulatorError.deviceNotBooted) {
      try await fake.screenshot(on: SampleID.iPhoneOff, to: Self.file)
    }
    await #expect(throws: SimulatorError.deviceNotFound) { try await fake.screenshot(on: Self.missing, to: Self.file) }
    #expect(fake.calls == [.screenshot(SampleID.iPhoneOff, Self.file), .screenshot(Self.missing, Self.file)])
  }

  @Test("설정한 에러는 상태보다 먼저 던진다")
  func configuredError() async throws {
    let fake = SimulatorClientFake(inventory: .sample)

    fake.setScreenshotError(.commandFailed)
    await #expect(throws: SimulatorError.commandFailed) {
      try await fake.screenshot(on: SampleID.iPhoneOn, to: Self.file)
    }
    await #expect(throws: SimulatorError.commandFailed) { try await fake.screenshot(on: Self.missing, to: Self.file) }
    fake.setScreenshotError(nil)
    try await fake.screenshot(on: SampleID.iPhoneOn, to: Self.file)
  }

  @Test("setScreenshotPNG 를 정하면 성공한 screenshot 이 그 바이트를 파일에 쓰고, 실패하면 쓰지 않는다")
  func writesConfiguredPNG() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "SimulatorFakePNG-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let written = directory.appending(path: "on.png")
    let skipped = directory.appending(path: "off.png")
    let png = Data([0x89, 0x50, 0x4E, 0x47])
    let fake = SimulatorClientFake(inventory: .sample)

    fake.setScreenshotPNG(png)
    try await fake.screenshot(on: SampleID.iPhoneOn, to: written)
    await #expect(throws: SimulatorError.deviceNotBooted) {
      try await fake.screenshot(on: SampleID.iPhoneOff, to: skipped)
    }

    #expect(try Data(contentsOf: written) == png)
    #expect(!FileManager.default.fileExists(atPath: skipped.path(percentEncoded: false)))
  }

  @Test("setScreenshotPNG 를 정하지 않으면 파일을 만들지 않는다")
  func noPNGByDefault() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "SimulatorFakePNG-\(UUID().uuidString).png")
    let fake = SimulatorClientFake(inventory: .sample)

    try await fake.screenshot(on: SampleID.iPhoneOn, to: file)

    #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
  }

  @Test("멈춘 screenshot 은 기록된 뒤 resume 까지 기다리고, 깨어난 뒤의 설정을 쓴다")
  func suspendScreenshots() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.suspendScreenshots()
    let task = Task { try await fake.screenshot(on: SampleID.iPhoneOn, to: Self.file) }
    while !fake.calls.contains(.screenshot(SampleID.iPhoneOn, Self.file)) {
      await Task.yield()
    }

    fake.setScreenshotError(.deviceNotBooted)
    fake.resumeScreenshots()

    await #expect(throws: SimulatorError.deviceNotBooted) { try await task.value }
    fake.setScreenshotError(nil)
    try await fake.screenshot(on: SampleID.iPhoneOn, to: Self.file)
  }
}
