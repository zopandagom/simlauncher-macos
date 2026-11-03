import AppLogInterface
import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import AppLogImpl

/// 다시 설치·다시 실행의 대체 표시와 창의 다시 실행.
struct AppLogClientImplReplacementTests {
  @Test("replacementWillStart 뒤에 끝나면 replaced 이고 목록을 읽지 않는다")
  func installReplaces() async throws {
    let fixture = AppLogFixture()
    let (id, run) = try await fixture.launched(run: 0)

    await fixture.client.replacementWillStart(AppLogFixture.app, on: SampleID.iPhoneOn)
    run.finish(.success(.exited))

    #expect(try await fixture.waitForEnd(of: id) == .replaced)
    #expect(!fixture.simulator.calls.contains(.fetchInventory))
  }

  @Test("replacementCancelled 로 되돌리면 끝날 때 appExited")
  func installCancelled() async throws {
    let fixture = AppLogFixture()
    let (id, run) = try await fixture.launched(run: 0)

    await fixture.client.replacementWillStart(AppLogFixture.app, on: SampleID.iPhoneOn)
    await fixture.client.replacementCancelled(AppLogFixture.app, on: SampleID.iPhoneOn)
    run.finish(.success(.exited))

    #expect(try await fixture.waitForEnd(of: id) == .appExited)
  }

  @Test("다른 앱·다른 기기의 다시 설치는 표시하지 않는다")
  func installOtherKey() async throws {
    let fixture = AppLogFixture()
    let (id, run) = try await fixture.launched(run: 0)

    await fixture.client.replacementWillStart(AppLogFixture.otherApp, on: SampleID.iPhoneOn)
    await fixture.client.replacementWillStart(AppLogFixture.app, on: SampleID.iPhoneOff)
    run.finish(.success(.exited))

    #expect(try await fixture.waitForEnd(of: id) == .appExited)
  }

  @Test("같은 기기·앱의 새 실행이 시작되면 앞 세션은 끝날 때 replaced (새 신호와 앞 끝의 순서와 무관)")
  func newLaunchReplaces() async throws {
    let fixture = AppLogFixture()
    let (first, firstRun) = try await fixture.launched(run: 0)
    let task = fixture.launch()
    let secondRun = try await fixture.console.run(1)

    // 앞 simctl 이 새 신호보다 먼저 끝난다.
    firstRun.finish(.success(.exited))
    #expect(try await fixture.waitForEnd(of: first) == .replaced)
    await secondRun.emit(.launched)
    let second = try await task.value

    #expect(await fixture.summaries().map(\.id) == [first, second])
  }

  @Test("새 실행이 신호 전에 실패하면 앞 세션의 표시를 되돌린다")
  func failedLaunchUnmarks() async throws {
    let fixture = AppLogFixture()
    let (first, firstRun) = try await fixture.launched(run: 0)
    let task = fixture.launch()
    let secondRun = try await fixture.console.run(1)

    secondRun.finish(.failure(.appLaunchFailed))
    await #expect(throws: AppLogLaunchError.appLaunchFailed) { try await task.value }
    firstRun.finish(.success(.exited))

    #expect(try await fixture.waitForEnd(of: first) == .appExited)
  }

  @Test("다른 앱의 새 실행은 앞 세션을 대체하지 않는다")
  func otherAppDoesNotReplace() async throws {
    let fixture = AppLogFixture()
    let (first, firstRun) = try await fixture.launched(run: 0)
    _ = try await fixture.launched(AppLogFixture.otherApp, run: 1)

    firstRun.finish(.success(.exited))

    #expect(try await fixture.waitForEnd(of: first) == .appExited)
  }

  @Test("다시 실행은 Simulator 앱을 연 뒤 같은 기기·앱으로 실행한다 (기기는 켜지 않는다)")
  func relaunch() async throws {
    let fixture = AppLogFixture()
    let (first, firstRun) = try await fixture.launched(run: 0)
    firstRun.finish(.success(.exited))
    _ = try await fixture.waitForEnd(of: first)

    let task = Task { try await fixture.client.relaunch(first) }
    let run = try await fixture.console.run(1)
    await run.emit(.launched)
    let second = try await task.value

    #expect(second != first)
    #expect(run.bundleID == AppLogFixture.app)
    #expect(run.device == SampleID.iPhoneOn)
    let calls = fixture.simulator.calls.filter { $0 != .fetchInventory }
    #expect(calls == [
      .launchWithConsole(AppLogFixture.app, SampleID.iPhoneOn),
      .openSimulatorApp,
      .launchWithConsole(AppLogFixture.app, SampleID.iPhoneOn),
    ])
    #expect(!calls.contains(.boot(SampleID.iPhoneOn)))
    #expect(await fixture.summaries().last?.state == .receiving)
  }

  @Test("Simulator 앱 열기가 실패해도 다시 실행한다, 실행 실패는 그대로 던진다")
  func relaunchIgnoresOpenFailure() async throws {
    let fixture = AppLogFixture()
    let (first, firstRun) = try await fixture.launched(run: 0)
    firstRun.finish(.success(.exited))
    _ = try await fixture.waitForEnd(of: first)
    fixture.simulator.setOpenAppError(.simulatorAppNotFound)

    let task = Task { try await fixture.client.relaunch(first) }
    let run = try await fixture.console.run(1)
    run.finish(.failure(.deviceNotBooted))

    await #expect(throws: AppLogLaunchError.deviceNotBooted) { try await task.value }
  }

  @Test("없는 세션의 다시 실행은 실행 없이 sessionNotFound")
  func relaunchMissing() async {
    let fixture = AppLogFixture()

    await #expect(throws: AppLogLaunchError.sessionNotFound) {
      try await fixture.client.relaunch(AppLogSessionID(UUID()))
    }
    #expect(fixture.simulator.calls.isEmpty)
  }
}
