import AndroidEmulatorInterface
import AndroidEmulatorTesting
import CommandInterface
import CommandTesting
import Core
import DevEnvironmentTesting
import Foundation
import ScreenLayoutInterface
import SimulatorTesting
import Synchronization
import Testing
@testable import ScreenLayoutImpl

struct ScreenLayoutClientImplTests {
  final class Phases: Sendable {
    private let phases = Mutex<[LayoutReadPhase]>([])

    func add(_ phase: LayoutReadPhase) {
      self.phases.withLock { $0.append(phase) }
    }

    var all: [LayoutReadPhase] {
      self.phases.withLock { $0 }
    }
  }

  /// Android 만 쓰는 Client (iOS 의존은 아무것도 하지 않는 Fake. 기기 이름을 물을 때만 `simulator` 를 쓴다).
  static func client(
    _ android: AndroidEmulatorClientFake,
    simulator: SimulatorClientFake = SimulatorClientFake()
  ) -> ScreenLayoutClientImpl {
    ScreenLayoutClientImpl(
      androidEmulator: android,
      simulator: simulator,
      devEnvironment: DevEnvironmentClientFake(),
      command: CommandClientFake { _ in CommandResult(exitCode: 0, stdout: Data(), stderr: Data()) },
      runnerDirectory: FileManager.default.temporaryDirectory.appending(path: "LayoutRunnerUnused-\(UUID().uuidString)")
    )
  }

  @Test("Android 대상: .reading 을 한 번 알린 뒤 AVD ID 로 맡기고 그 스냅샷을 돌려준다")
  func android() async throws {
    let android = AndroidEmulatorClientFake()
    let client = Self.client(android)
    let phases = Phases()

    let snapshot = try await client.snapshot(of: .android(AndroidVirtualDevice.ID("Pixel_9"))) { phases.add($0) }

    #expect(snapshot == .androidLayoutSample)
    #expect(phases.all == [.reading])
    #expect(android.calls == [.layoutSnapshot(AndroidVirtualDevice.ID("Pixel_9"))])
  }

  @Test("iOS 기기 이름은 시뮬레이터 목록에서 그 UDID 의 이름이고, 없거나 목록을 읽지 못하면 nil 이다")
  func iOSDeviceName() async throws {
    let simulator = SimulatorClientFake(inventory: .sample)
    let client = Self.client(AndroidEmulatorClientFake(), simulator: simulator)
    let device = try #require(DeviceInventory.sample.devices.first)

    #expect(await client.deviceName(of: .iOS(device.id)) == device.name)
    #expect(await client.deviceName(of: .iOS(VirtualDevice.ID("00000000-0000-0000-0000-000000000000"))) == nil)
    simulator.setFetchError(.developerToolsUnavailable)
    #expect(await client.deviceName(of: .iOS(device.id)) == nil)
  }

  @Test("Android 기기 이름은 묻지 않고 nil 이다 (스냅샷이 이름을 가져온다)")
  func androidDeviceName() async {
    let android = AndroidEmulatorClientFake()
    let client = Self.client(android)

    #expect(await client.deviceName(of: .android(AndroidVirtualDevice.ID("Pixel_9"))) == nil)
    #expect(android.calls.isEmpty)
  }

  @Test("Android 실패는 레이아웃 실패로 옮겨 던진다")
  func androidFailure() async throws {
    let android = AndroidEmulatorClientFake()
    android.setLayoutSnapshotResult(.failure(.layoutNotIdle))
    let client = Self.client(android)

    await #expect(throws: ScreenLayoutError.screenNotIdle) {
      try await client.snapshot(of: .android(AndroidVirtualDevice.ID("Pixel_9"))) { _ in }
    }
  }

  @Test(
    "오류 매핑 표",
    arguments: [
      (AndroidEmulatorError.deviceNotFound, ScreenLayoutError.deviceNotFound),
      (.deviceUnavailable(.folderMissing), .deviceUnavailable),
      (.deviceNotBooted, .deviceNotBooted),
      (.sdkUnavailable, .toolsUnavailable),
      (.adbUnavailable, .toolsUnavailable),
      (.layoutNotIdle, .screenNotIdle),
      (.layoutDisplayOff, .displayOff),
      (.layoutBusy, .automationBusy),
      (.layoutTimedOut, .timedOut),
      (.layoutUnreadable, .unreadable),
      (.captureFailed, .unreadable),
      (.cancelled, .cancelled),
      (.appCommandFailed, .unreadable),
      (.recordingFailed, .unreadable),
      (.installTimedOut, .unreadable),
    ]
  )
  func errorMapping(android: AndroidEmulatorError, expected: ScreenLayoutError) {
    #expect(ScreenLayoutError(android) == expected)
  }
}
