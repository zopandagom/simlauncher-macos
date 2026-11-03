import AppLogInterface
import AppLogTesting
import Core
import Foundation
import Testing

struct AppLogClientFakeTests {
  private static let app = AppBundleID("com.example.app")!
  private static let failingApp = AppBundleID("com.example.fail")!
  private static let device = VirtualDevice.ID("00000000-0000-0000-0000-000000000002")

  @Test("launchIOSApp 은 기록하고 받는 중 요약을 더한다, 처리기가 던지면 세션이 없다")
  func launch() async throws {
    let fake = AppLogClientFake { bundleID, _ throws(AppLogLaunchError) in
      if bundleID.rawValue == "com.example.fail" {
        throw .appNotInstalled
      }
    }

    let id = try await fake.launchIOSApp(Self.app, appName: "App", on: Self.device, deviceName: "iPhone")
    await #expect(throws: AppLogLaunchError.appNotInstalled) {
      try await fake.launchIOSApp(
        #require(AppBundleID("com.example.fail")),
        appName: "F",
        on: Self.device,
        deviceName: "iPhone"
      )
    }

    #expect(fake.sessions.map(\.id) == [id])
    #expect(fake.sessions.first?.state == .receiving)
    #expect(fake.sessions.first?.target == .iOS(Self.device))
    #expect(try fake.calls == [
      .launchIOSApp(Self.app, Self.device),
      .launchIOSApp(#require(AppBundleID("com.example.fail")), Self.device),
    ])
  }

  @Test("sessionUpdates 는 지금 목록부터, lineUpdates 는 스냅숏부터 보내고 구독 끝을 센다")
  func streams() async throws {
    let id = AppLogSessionID(UUID())
    let fake = AppLogClientFake(sessions: [Self.summary(id)])
    fake.append(["a"], to: id)

    var sessions = await fake.sessionUpdates().makeAsyncIterator()
    #expect(await sessions.next()?.map(\.id) == [id])

    let lines = await Collector(fake.lineUpdates(of: id))
    try await waitUntil { fake.activeLineSubscriptions(of: id) == 1 && lines.values.count == 1 }
    fake.append(["b"], to: id)
    try await waitUntil { lines.values.count == 2 }

    #expect(lines.values == [
      AppLogLineUpdate(isSnapshot: true, lines: [AppLogLine(index: 0, text: "a")], droppedCount: 0),
      AppLogLineUpdate(isSnapshot: false, lines: [AppLogLine(index: 1, text: "b")], droppedCount: 0),
    ])
    lines.cancel()
    try await waitUntil { fake.activeLineSubscriptions(of: id) == 0 }
  }

  @Test("remove 는 줄 구독을 끝내고, 없는 세션의 줄 구독은 곧바로 끝난다")
  func removeFinishesLines() async {
    let id = AppLogSessionID(UUID())
    let fake = AppLogClientFake(sessions: [Self.summary(id)])
    let task = Task { () -> Int in
      var count = 0
      for await _ in await fake.lineUpdates(of: id) {
        count += 1
      }
      return count
    }
    while fake.activeLineSubscriptions(of: id) == 0 {
      await Task.yield()
    }

    fake.remove(id)

    #expect(await task.value == 1)
    var missing = await fake.lineUpdates(of: id).makeAsyncIterator()
    #expect(await missing.next() == nil)
  }

  @Test("relaunch 는 기본으로 같은 기기·앱의 받는 중 세션을 더하고, 결과를 정하거나 멈출 수 있다")
  func relaunch() async throws {
    let id = AppLogSessionID(UUID())
    let fake = AppLogClientFake(sessions: [Self.summary(id, state: .ended(.appExited))])

    let second = try await fake.relaunch(id)
    #expect(fake.sessions.last?.id == second)
    #expect(fake.sessions.last?.appID == "com.example.app")
    #expect(fake.sessions.last?.state == .receiving)

    fake.setRelaunchResult(.failure(.deviceNotBooted))
    await #expect(throws: AppLogLaunchError.deviceNotBooted) { try await fake.relaunch(id) }

    fake.setRelaunchResult(nil)
    fake.suspendRelaunches()
    let task = Task { try await fake.relaunch(id) }
    while fake.calls.count < 3 {
      await Task.yield()
    }
    fake.resumeRelaunches()
    _ = try await task.value
    await #expect(throws: AppLogLaunchError.sessionNotFound) { try await fake.relaunch(AppLogSessionID(UUID())) }
    #expect(fake.calls.count == 4)
  }

  @Test("stopAll·대체 알림을 기록한다")
  func records() async {
    let fake = AppLogClientFake()

    await fake.replacementWillStart(Self.app, on: Self.device)
    await fake.replacementCancelled(Self.app, on: Self.device)
    fake.stopAll()

    #expect(fake.calls == [.replacementWillStart(Self.app, Self.device), .replacementCancelled(Self.app, Self.device)])
    #expect(fake.stopAllCount == 1)
  }

  private static func summary(_ id: AppLogSessionID, state: AppLogSessionState = .receiving) -> AppLogSessionSummary {
    AppLogSessionSummary(
      id: id,
      target: .iOS(self.device),
      deviceName: "iPhone",
      appID: self.app.rawValue,
      appName: "App",
      startedAt: Date(timeIntervalSince1970: 0),
      state: state
    )
  }
}
