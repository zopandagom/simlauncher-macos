import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Testing

/// Feature 테스트·Example 이 기대는 Fake 동작.
struct AndroidEmulatorClientFakeTests {
  @Test("켜기·끄기는 목록 상태를 바꾸고 호출을 기록한다, 기기별 켜기 에러가 먼저다")
  func bootAndShutdown() async throws {
    let fake = AndroidEmulatorClientFake(inventory: .sample)
    let phone = AndroidVirtualDevice.phoneSample.id

    try await fake.boot(phone)
    #expect(try await fake.fetchDevices().devices.first { $0.id == phone }?.state == .booted)
    try await fake.shutdown(phone)
    #expect(fake.inventory.devices.first { $0.id == phone }?.state == .shutdown)

    fake.setBootError(.bootTimedOut)
    fake.setBootError(.emulatorExited(1), for: phone)
    await #expect(throws: AndroidEmulatorError.emulatorExited(1)) { try await fake.boot(phone) }
    let tablet = AndroidVirtualDevice.bootedTabletSample.id
    await #expect(throws: AndroidEmulatorError.bootTimedOut) { try await fake.boot(tablet) }
    #expect(fake.calls == [.boot(phone), .fetchDevices, .shutdown(phone), .boot(phone), .boot(tablet)])
  }

  @Test("만들기: Impl 과 같은 순서로 검사하고 꺼진 새 기기를 더한다")
  func create() async throws {
    let fake = AndroidEmulatorClientFake(inventory: .sample)

    let id = try await fake.create(displayName: " 테스트 폰 ", image: .sample, profile: .tablet)
    #expect(id == AndroidVirtualDevice.ID("Android_Device_2"))
    #expect(fake.inventory.devices.last == AndroidVirtualDevice(
      id: id,
      displayName: "테스트 폰",
      systemImage: .sample,
      formFactor: .tablet,
      state: .shutdown,
      availability: .available
    ))

    await #expect(throws: AndroidEmulatorError.invalidDeviceName(.empty)) {
      _ = try await fake.create(displayName: " ", image: .sample, profile: .phone)
    }
    let missing = try #require(AndroidSystemImageRef(apiFolder: "android-35", tag: "google_apis", abi: "arm64-v8a"))
    await #expect(throws: AndroidEmulatorError.creationOptionUnavailable) {
      _ = try await fake.create(displayName: "Phone", image: missing, profile: .phone)
    }
  }

  @Test("삭제는 설정한 결과를 돌려주고 성공이면 목록에서 뺀다, 초기화는 목록을 바꾸지 않는다")
  func deleteAndErase() async throws {
    let fake = AndroidEmulatorClientFake(inventory: .sample)
    let phone = AndroidVirtualDevice.phoneSample.id
    let kept = URL(filePath: "/Users/fake/Documents", directoryHint: .isDirectory)

    try await fake.erase(phone)
    #expect(fake.inventory == .sample)
    fake.setDeleteResult(.success(.folderKept(kept)))
    #expect(try await fake.delete(phone) == .folderKept(kept))
    #expect(!fake.inventory.devices.contains { $0.id == phone })
    fake.setDeleteResult(.failure(.deviceRunning))
    await #expect(throws: AndroidEmulatorError.deviceRunning) {
      _ = try await fake.delete(AndroidVirtualDevice.bootedTabletSample.id)
    }
    #expect(fake.inventory.devices.contains { $0.id == AndroidVirtualDevice.bootedTabletSample.id })
  }

  @Test("멈춘 기기의 켜기는 재개까지 기다리고 다른 기기는 기다리지 않는다")
  func suspendBootOfDevice() async throws {
    let fake = AndroidEmulatorClientFake(inventory: .sample)
    let phone = AndroidVirtualDevice.phoneSample.id
    let tablet = AndroidVirtualDevice.bootedTabletSample.id
    fake.suspendBoot(of: phone)

    let waiting = Task { try await fake.boot(phone) }
    try await fake.boot(tablet)
    while !fake.calls.contains(.boot(phone)) {
      await Task.yield()
    }
    #expect(fake.inventory.devices.first { $0.id == phone }?.state == .shutdown)
    fake.resumeBoot(of: phone)
    try await waiting.value
    #expect(fake.inventory.devices.first { $0.id == phone }?.state == .booted)
  }
}
