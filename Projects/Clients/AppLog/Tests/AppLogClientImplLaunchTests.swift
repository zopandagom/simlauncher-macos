import AppLogInterface
import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import AppLogImpl

/// 실행·신호·실패·끝남 판정·멈춤.
struct AppLogClientImplLaunchTests {
  @Test("신호를 받으면 돌아오고 받는 중 요약이 보인다")
  func launchSucceeds() async throws {
    let fixture = AppLogFixture()

    let (id, run) = try await fixture.launched(run: 0)

    #expect(run.bundleID == AppLogFixture.app)
    #expect(run.device == SampleID.iPhoneOn)
    let summary = try #require(await fixture.summaries().first)
    #expect(summary.id == id)
    #expect(summary.target == .iOS(SampleID.iPhoneOn))
    #expect(summary.appID == "dev.simlauncher.logprobe")
    #expect(summary.appName == "LogProbe")
    #expect(summary.deviceName == "iPhone 17 Pro")
    #expect(summary.state == .receiving)
    #expect(fixture.simulator.calls == [.launchWithConsole(AppLogFixture.app, SampleID.iPhoneOn)])
  }

  @Test("신호 전에 온 줄도 스냅숏에 든다, 신호 전에는 목록에 없다")
  func linesBeforeSignal() async throws {
    let fixture = AppLogFixture()
    let task = fixture.launch()
    let run = try await fixture.console.run(0)

    await run.emit(.lines(["probe start"]))
    #expect(await fixture.summaries().isEmpty)
    await run.emit(.launched)
    let id = try await task.value

    let lines = await Collector(fixture.client.lineUpdates(of: id))
    try await waitUntil { lines.values.count == 1 }
    let snapshot = try #require(lines.values.first)
    #expect(snapshot.isSnapshot)
    #expect(snapshot.lines == [AppLogLine(index: 0, text: "probe start")])
    #expect(snapshot.droppedCount == 0)
  }

  @Test(
    "신호 전 실패는 같은 이름으로 던지고 세션은 생기지 않는다",
    arguments: [
      (SimulatorError.developerToolsUnavailable, AppLogLaunchError.developerToolsUnavailable),
      (.deviceNotFound, .deviceNotFound),
      (.deviceNotBooted, .deviceNotBooted),
      (.appNotInstalled, .appNotInstalled),
      (.appLaunchFailed, .appLaunchFailed),
      (.commandFailed, .commandFailed),
      (.appInvalid, .commandFailed),
    ]
  )
  func failureBeforeSignal(error: SimulatorError, expected: AppLogLaunchError) async throws {
    let fixture = AppLogFixture()
    let task = fixture.launch()
    let run = try await fixture.console.run(0)

    await run.emit(.lines(["noise"]))
    run.finish(.failure(error))

    await #expect(throws: expected) { try await task.value }
    #expect(await fixture.summaries().isEmpty)
  }

  @Test("신호 없이 0 으로 끝나면 성공이고 그 세션은 곧바로 끝난다")
  func exitWithoutSignal() async throws {
    let fixture = AppLogFixture()
    let task = fixture.launch()
    let run = try await fixture.console.run(0)

    run.finish(.success(.exited))
    let id = try await task.value

    #expect(try await fixture.waitForEnd(of: id) == .appExited)
  }

  @Test(
    "끝나면 목록을 다시 읽어 켜져 있으면 appExited, 꺼졌거나 끄는 중이거나 없으면 deviceShutDown",
    arguments: [
      (VirtualDevice.State.booted, AppLogEndReason.appExited),
      (.shutdown, .deviceShutDown),
      (.shuttingDown, .deviceShutDown),
      (.booting, .deviceShutDown),
    ]
  )
  func endReasonFromInventory(state: VirtualDevice.State, expected: AppLogEndReason) async throws {
    let fixture = AppLogFixture()
    let (id, run) = try await fixture.launched(run: 0)
    fixture.simulator.setInventory(Self.inventory(iPhoneOnState: state))

    run.finish(.success(.exited))

    #expect(try await fixture.waitForEnd(of: id) == expected)
  }

  @Test("목록에서 기기가 사라졌으면 deviceShutDown, 목록을 읽지 못하면 appExited")
  func endReasonMissingOrUnreadable() async throws {
    let fixture = AppLogFixture()
    let (first, firstRun) = try await fixture.launched(run: 0)
    let (second, secondRun) = try await fixture.launched(AppLogFixture.otherApp, run: 1)

    fixture.simulator.setInventory(DeviceInventory(devices: [], runtimes: [], deviceTypes: []))
    firstRun.finish(.success(.exited))
    #expect(try await fixture.waitForEnd(of: first) == .deviceShutDown)

    fixture.simulator.setFetchError(.commandFailed)
    secondRun.finish(.success(.exited))
    #expect(try await fixture.waitForEnd(of: second) == .appExited)
  }

  @Test("신호 뒤의 실패도 끝남 판정만 한다")
  func failureAfterSignal() async throws {
    let fixture = AppLogFixture()
    let (id, run) = try await fixture.launched(run: 0)

    run.finish(.failure(.commandFailed))

    #expect(try await fixture.waitForEnd(of: id) == .appExited)
  }

  @Test("stopAll 은 받기를 취소해(→ .stopped) 세션을 stopped 로 끝내고, 이후 실행·다시 실행은 commandFailed")
  func stopAll() async throws {
    let fixture = AppLogFixture()
    let (id, run) = try await fixture.launched(run: 0)

    fixture.client.stopAll()

    #expect(try await fixture.waitForEnd(of: id) == .stopped)
    #expect(run.wasCancelled)
    await #expect(throws: AppLogLaunchError.commandFailed) { try await fixture.launch().value }
    await #expect(throws: AppLogLaunchError.commandFailed) { try await fixture.client.relaunch(id) }
    #expect(fixture.console.count == 1)
  }

  @Test("신호 전에 stopAll 이 오면 실행은 commandFailed 이고 세션은 없다")
  func stopAllBeforeSignal() async throws {
    let fixture = AppLogFixture()
    let task = fixture.launch()
    let run = try await fixture.console.run(0)

    fixture.client.stopAll()

    await #expect(throws: AppLogLaunchError.commandFailed) { try await task.value }
    #expect(run.wasCancelled)
    #expect(await fixture.summaries().isEmpty)
  }

  @Test("신호도 끝남도 없이 대기 상한이 지나면 성공으로 보고 받는 중으로 공개한다")
  func signalTimeout() async throws {
    let fixture = AppLogFixture(launchSignalTimeout: .milliseconds(50))
    let task = fixture.launch()
    let run = try await fixture.console.run(0)

    let id = try await task.value

    #expect(await fixture.summaries().map(\.id) == [id])
    #expect(await fixture.summaries().first?.state == .receiving)
    run.finish(.failure(.appLaunchFailed))
    #expect(try await fixture.waitForEnd(of: id) == .appExited)
  }

  @Test("sessionUpdates 의 첫 알림은 지금 목록, 그 뒤는 바뀔 때마다")
  func sessionUpdates() async throws {
    let fixture = AppLogFixture()
    let (first, _) = try await fixture.launched(run: 0)
    let updates = await Collector(fixture.client.sessionUpdates())
    try await waitUntil { updates.values.count == 1 }
    #expect(updates.values.first?.map(\.id) == [first])

    let (second, _) = try await fixture.launched(AppLogFixture.otherApp, run: 1)

    try await waitUntil { updates.last?.count == 2 }
    #expect(updates.last?.map(\.id) == [first, second])
    updates.cancel()
  }

  /// 샘플 목록에서 켜진 iPhone 의 상태만 바꾼다.
  private static func inventory(iPhoneOnState state: VirtualDevice.State) -> DeviceInventory {
    let sample = DeviceInventory.sample
    let devices = sample.devices.map { device in
      guard device.id == SampleID.iPhoneOn else { return device }
      return VirtualDevice(
        id: device.id,
        name: device.name,
        family: device.family,
        state: state,
        availability: device.availability,
        runtime: device.runtime
      )
    }
    return DeviceInventory(devices: devices, runtimes: sample.runtimes, deviceTypes: sample.deviceTypes)
  }
}
