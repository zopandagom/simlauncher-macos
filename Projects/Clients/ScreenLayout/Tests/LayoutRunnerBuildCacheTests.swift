import Core
import DevEnvironmentTesting
import Foundation
import ScreenLayoutInterface
import SimulatorTesting
import Testing
@testable import ScreenLayoutImpl

/// 러너 빌드 캐시의 정리 (Fake Command·Simulator·DevEnvironment + 흉내 러너).
@Suite(.timeLimit(.minutes(1)))
struct LayoutRunnerBuildCacheTests {
  @Test("먼저 시작해 늦게 끝난 빌드가, 그 사이 다른 Xcode 로 준비 중인 기기의 빌드를 지우지 않는다")
  func laterBuildKeepsKeyInUse() async throws {
    let deviceB = RunnerHarness.device
    let deviceC = VirtualDevice.ID("00000000-0000-0000-0000-000000000003")
    let harness = RunnerHarness(
      timing: IOSLayoutReaderTests.longReadyTiming,
      inventory: RunnerHarness.inventory(deviceC, state: .booted)
    )

    // (1) B: beta 키로 빌드를 시작해 처리기 안 게이트에서 멈춘다.
    let gateB = Gate()
    harness.update { $0.buildGate = gateB }
    harness.devEnvironment.setStatus(.ready(.beta))
    let taskB = harness.readTask(deviceB)
    #expect(try await waitUntil { gateB.isWaiting })

    // (2) C: 기본 Xcode 키로 빌드·launch 하고 ready 전 준비 중에 머문다. 처리기는 호출 때 게이트를 읽어 B 에 닿지 않는다.
    harness.update { state in
      state.buildGate = nil
      state.launch = .neverReady
    }
    harness.devEnvironment.setStatus(.ready(.sample))
    let taskC = harness.readTask(deviceC)
    #expect(try await waitUntil { harness.launches.count == 1 })

    // (3) B 의 빌드를 끝낸다 (빌드 뒤 정리 → launch → 읽기).
    harness.update { $0.launch = .serve }
    gateB.open()
    _ = try await taskB.value.get()

    // (4) C 가 쓰는 키의 빌드가 남는다.
    let builds = harness.root.appending(path: "builds", directoryHint: .isDirectory)
    #expect(try FileManager.default.contentsOfDirectory(atPath: builds.path(percentEncoded: false)).count == 2)

    // (5) 정리.
    await harness.client.stopAllIOSRunners()
    _ = await taskC.value
  }
}
