import AndroidEmulatorInterface
import AndroidEmulatorTesting
import AppLogInterface
import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import AppLogImpl

/// Android 실행(`launchWithLogcat`)의 세션 공개·실패 변환·끝남 판정·대체·다시 실행. Simulator 는 부르지 않는다.
struct AppLogClientImplAndroidTests {
  // MARK: - 실행

  @Test(".launched 를 받으면 .android 대상의 받는 중 세션을 공개하고, 줄이 버퍼·구독으로 온다")
  func launchSucceeds() async throws {
    let fixture = AppLogFixture()

    let (id, run) = try await fixture.launchedAndroid(run: 0)
    await run.emit(.lines(["11-09 a", "11-09 b"]))

    #expect(run.package == AppLogFixture.package)
    #expect(run.device == AppLogFixture.avd)
    let summary = try #require(await fixture.summaries().first)
    #expect(summary.id == id)
    #expect(summary.target == .android(AppLogFixture.avd))
    #expect(summary.appID == "dev.simlauncher.sample")
    #expect(summary.appName == "dev.simlauncher.sample")
    #expect(summary.deviceName == "Android Device")
    #expect(summary.state == .receiving)
    let lines = await Collector(fixture.client.lineUpdates(of: id))
    try await waitUntil { lines.values.flatMap(\.lines).count == 2 }
    #expect(lines.values.flatMap(\.lines).map(\.text) == ["11-09 a", "11-09 b"])
    lines.cancel()
    #expect(fixture.emulator.calls == [.launchWithLogcat(AppLogFixture.package, AppLogFixture.avd)])
    #expect(fixture.simulator.calls.isEmpty)
  }

  @Test(
    ".launched 전 실패는 흔한 것은 같은 뜻의 케이스로, 그 밖은 commandFailed 로 던지고 세션은 생기지 않는다",
    arguments: [
      (AndroidEmulatorError.sdkUnavailable, AppLogLaunchError.developerToolsUnavailable),
      (.deviceNotFound, .deviceNotFound),
      (.deviceUnavailable(.unsupportedName), .deviceUnavailable(.unsupportedName)),
      (.deviceNotBooted, .deviceNotBooted),
      (.launchFailed(.notInstalled), .appNotInstalled),
      (.launchFailed(.noLauncherActivity), .noLauncherActivity),
      (.adbUnavailable, .adbUnavailable),
      (.appCommandFailed, .commandFailed),
      (.avdFolderUnavailable, .commandFailed),
    ]
  )
  func failureBeforeLaunched(error: AndroidEmulatorError, expected: AppLogLaunchError) async throws {
    let fixture = AppLogFixture()
    let task = fixture.launchAndroid()
    let run = try await fixture.logcat.run(0)

    run.finish(.failure(error))

    await #expect(throws: expected) { try await task.value }
    #expect(await fixture.summaries().isEmpty)
  }

  // MARK: - 끝

  @Test(
    "끝: appExited → appExited, connectionLost → deviceShutDown (목록을 읽지 않는다)",
    arguments: [
      (AndroidLogcatEnd.appExited, AppLogEndReason.appExited),
      (.connectionLost, .deviceShutDown),
    ]
  )
  func endReason(end: AndroidLogcatEnd, expected: AppLogEndReason) async throws {
    let fixture = AppLogFixture()
    let (id, run) = try await fixture.launchedAndroid(run: 0)

    run.finish(.success(end))

    #expect(try await fixture.waitForEnd(of: id) == expected)
    #expect(fixture.simulator.calls.isEmpty)
  }

  @Test("stopAll 뒤 .stopped 는 stopped 로 끝난다")
  func stopAll() async throws {
    let fixture = AppLogFixture()
    let (id, run) = try await fixture.launchedAndroid(run: 0)

    fixture.client.stopAll()

    #expect(try await fixture.waitForEnd(of: id) == .stopped)
    #expect(run.wasCancelled)
    await #expect(throws: AppLogLaunchError.commandFailed) { try await fixture.launchAndroid().value }
  }

  @Test(".launched 없이 끝나면(stopped·connectionLost) commandFailed 를 던지고 세션은 없다")
  func endBeforeLaunched() async throws {
    for end in [AndroidLogcatEnd.stopped, .connectionLost] {
      let fixture = AppLogFixture()
      let task = fixture.launchAndroid()
      let run = try await fixture.logcat.run(0)

      run.finish(.success(end))

      await #expect(throws: AppLogLaunchError.commandFailed) { try await task.value }
      #expect(await fixture.summaries().isEmpty)
      #expect(fixture.simulator.calls.isEmpty)
    }
  }

  @Test("신호 대기 상한 뒤의 실패는 appExited 로 끝난다")
  func failureAfterTimeout() async throws {
    let fixture = AppLogFixture(launchSignalTimeout: .milliseconds(50))
    let task = fixture.launchAndroid()
    let run = try await fixture.logcat.run(0)
    let id = try await task.value

    run.finish(.failure(.appCommandFailed))

    #expect(try await fixture.waitForEnd(of: id) == .appExited)
    #expect(fixture.simulator.calls.isEmpty)
  }

  // MARK: - 대체

  @Test("같은 기기·패키지의 새 실행이 시작된 뒤 앞 세션이 appExited 로 끝나면 replaced")
  func newLaunchReplaces() async throws {
    let fixture = AppLogFixture()
    let (first, firstRun) = try await fixture.launchedAndroid(run: 0)
    let task = fixture.launchAndroid()
    let secondRun = try await fixture.logcat.run(1)

    // 새 실행의 force-stop 이 앞 앱을 끝내 앞 adb 가 143 으로 먼저 끝난다.
    firstRun.finish(.success(.appExited))
    #expect(try await fixture.waitForEnd(of: first) == .replaced)
    await secondRun.emit(.launched)
    let second = try await task.value

    #expect(await fixture.summaries().map(\.id) == [first, second])
    #expect(await fixture.summaries().last?.state == .receiving)
  }

  @Test("replacementWillStart 뒤 끝나면 replaced, replacementCancelled 로 되돌리면 appExited")
  func installMarks() async throws {
    let fixture = AppLogFixture()
    let (first, firstRun) = try await fixture.launchedAndroid(run: 0)
    let (second, secondRun) = try await fixture.launchedAndroid(AppLogFixture.otherPackage, run: 1)

    await fixture.client.replacementWillStart(AppLogFixture.package, on: AppLogFixture.avd)
    firstRun.finish(.success(.connectionLost))
    #expect(try await fixture.waitForEnd(of: first) == .replaced)

    await fixture.client.replacementWillStart(AppLogFixture.otherPackage, on: AppLogFixture.avd)
    await fixture.client.replacementCancelled(AppLogFixture.otherPackage, on: AppLogFixture.avd)
    secondRun.finish(.success(.appExited))
    #expect(try await fixture.waitForEnd(of: second) == .appExited)
  }

  @Test("다른 기기·다른 패키지·같은 문자열의 iOS 번들 ID 는 대체하지 않는다")
  func otherKeysDoNotReplace() async throws {
    let fixture = AppLogFixture()
    let (id, run) = try await fixture.launchedAndroid(run: 0)
    let sameString = try #require(AppBundleID(AppLogFixture.package.rawValue))

    await fixture.client.replacementWillStart(AppLogFixture.package, on: AppLogFixture.otherAVD)
    await fixture.client.replacementWillStart(AppLogFixture.otherPackage, on: AppLogFixture.avd)
    await fixture.client.replacementWillStart(sameString, on: SampleID.iPhoneOn)
    let other = fixture.launchAndroid(AppLogFixture.package, on: AppLogFixture.otherAVD)
    let otherRun = try await fixture.logcat.run(1)
    await otherRun.emit(.launched)
    _ = try await other.value
    run.finish(.success(.appExited))

    #expect(try await fixture.waitForEnd(of: id) == .appExited)
  }

  // MARK: - 다시 실행

  @Test("다시 실행: Simulator 호출 없이 같은 패키지·기기로 다시 받고 새 세션 ID, 실패는 그대로 던진다")
  func relaunch() async throws {
    let fixture = AppLogFixture()
    let (first, firstRun) = try await fixture.launchedAndroid(run: 0)
    firstRun.finish(.success(.appExited))
    _ = try await fixture.waitForEnd(of: first)

    let task = Task { try await fixture.client.relaunch(first) }
    let run = try await fixture.logcat.run(1)
    await run.emit(.launched)
    let second = try await task.value

    #expect(second != first)
    #expect(run.package == AppLogFixture.package)
    #expect(run.device == AppLogFixture.avd)
    #expect(await fixture.summaries().first { $0.id == second }?.target == .android(AppLogFixture.avd))

    let failing = Task { try await fixture.client.relaunch(first) }
    try await fixture.logcat.run(2).finish(.failure(.deviceNotBooted))
    await #expect(throws: AppLogLaunchError.deviceNotBooted) { try await failing.value }
    #expect(fixture.simulator.calls.isEmpty)
  }

  @Test("정리된 Android 세션의 다시 실행은 실행 없이 sessionNotFound")
  func relaunchRemoved() async throws {
    var limits = AppLogLimits.standard
    limits.sessionsPerDevice = 1
    let fixture = AppLogFixture(limits: limits)
    let (first, firstRun) = try await fixture.launchedAndroid(run: 0)
    firstRun.finish(.success(.appExited))
    _ = try await fixture.waitForEnd(of: first)
    _ = try await fixture.launchedAndroid(AppLogFixture.otherPackage, run: 1)

    await #expect(throws: AppLogLaunchError.sessionNotFound) { try await fixture.client.relaunch(first) }
    #expect(fixture.logcat.count == 2)
  }
}
