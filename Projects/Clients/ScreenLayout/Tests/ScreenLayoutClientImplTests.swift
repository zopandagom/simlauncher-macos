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

  /// Android 만 쓰는 Client (iOS 의존은 아무것도 하지 않는 Fake).
  static func client(_ android: AndroidEmulatorClientFake) -> ScreenLayoutClientImpl {
    ScreenLayoutClientImpl(
      androidEmulator: android,
      simulator: SimulatorClientFake(),
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
