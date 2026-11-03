import AppLogInterface
import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import AppLogImpl

/// 줄 버퍼·구독·묶음 알림·기기당 세션 정리.
struct AppLogClientImplLinesTests {
  @Test("줄 상한을 넘으면 앞을 버리고 droppedCount 를 알린다")
  func lineLimit() async throws {
    let fixture = AppLogFixture(limits: AppLogLimits(maxLines: 3, maxBytes: 1000, sessionsPerDevice: 5))
    let (id, run) = try await fixture.launched(run: 0)
    let updates = await Collector(fixture.client.lineUpdates(of: id))
    try await waitUntil { updates.values.count == 1 }

    await run.emit(.lines(["a", "b", "c", "d", "e"]))

    try await waitUntil { updates.values.count == 2 }
    let update = try #require(updates.last)
    #expect(!update.isSnapshot)
    #expect(update.lines == [
      AppLogLine(index: 2, text: "c"),
      AppLogLine(index: 3, text: "d"),
      AppLogLine(index: 4, text: "e"),
    ])
    #expect(update.droppedCount == 2)
    updates.cancel()
  }

  @Test("바이트 상한을 넘으면 줄 수와 관계없이 앞을 버린다")
  func byteLimit() async throws {
    let fixture = AppLogFixture(limits: AppLogLimits(maxLines: 100, maxBytes: 5, sessionsPerDevice: 5))
    let (id, run) = try await fixture.launched(run: 0)

    await run.emit(.lines(["aaa", "bbb", "c"]))

    let snapshot = try await Self.snapshot(fixture, id)
    #expect(snapshot.lines == [AppLogLine(index: 1, text: "bbb"), AppLogLine(index: 2, text: "c")])
    #expect(snapshot.droppedCount == 1)
  }

  @Test("중간에 구독하면 스냅숏 뒤에 새 줄만 온다 (중복 없음)")
  func lateSubscriberGetsNoDuplicates() async throws {
    let fixture = AppLogFixture()
    let (id, run) = try await fixture.launched(run: 0)
    await run.emit(.lines(["1", "2"]))

    let updates = await Collector(fixture.client.lineUpdates(of: id))
    try await waitUntil { updates.values.count == 1 }
    await run.emit(.lines(["3"]))
    await run.emit(.lines(["4"]))

    try await waitUntil { updates.values.count == 3 }
    #expect(updates.values.map { $0.lines.map(\.text) } == [["1", "2"], ["3"], ["4"]])
    #expect(updates.values.map(\.isSnapshot) == [true, false, false])
    updates.cancel()
  }

  @Test("묶음 간격이 있으면 그 사이 줄을 한 번에 보내고, 끝나면 남은 줄을 곧바로 보낸다")
  func batching() async throws {
    let fixture = AppLogFixture(flushInterval: .seconds(30))
    let (id, run) = try await fixture.launched(run: 0)
    let updates = await Collector(fixture.client.lineUpdates(of: id))
    try await waitUntil { updates.values.count == 1 }

    await run.emit(.lines(["a"]))
    await run.emit(.lines(["b"]))
    try await Task.sleep(for: .milliseconds(50))
    #expect(updates.values.count == 1)
    run.finish(.success(.exited))

    try await waitUntil { updates.values.count == 2 }
    #expect(updates.last?.lines.map(\.text) == ["a", "b"])
    updates.cancel()
  }

  @Test("없는 세션의 줄 구독은 곧바로 끝난다")
  func missingSessionFinishes() async throws {
    let fixture = AppLogFixture()

    let updates = await Collector(fixture.client.lineUpdates(of: AppLogSessionID(UUID())))

    try await waitUntil { updates.isFinished }
    #expect(updates.values.isEmpty)
  }

  @Test("기기당 상한을 넘으면 끝난 세션 중 오래된 것부터 지우고 그 줄 구독을 끝낸다, 받는 중 세션은 지우지 않는다")
  func prunesEndedSessions() async throws {
    let fixture = AppLogFixture(limits: AppLogLimits(maxLines: 100, maxBytes: 1000, sessionsPerDevice: 2))
    let apps = ["a.one", "a.two", "a.three", "a.four"].map { AppBundleID($0)! }
    let (first, firstRun) = try await fixture.launched(apps[0], run: 0)
    let (second, _) = try await fixture.launched(apps[1], run: 1)
    firstRun.finish(.success(.exited))
    _ = try await fixture.waitForEnd(of: first)
    let firstLines = await Collector(fixture.client.lineUpdates(of: first))
    try await waitUntil { firstLines.values.count == 1 }

    let (third, _) = try await fixture.launched(apps[2], run: 2)

    try await waitUntil { firstLines.isFinished }
    #expect(await fixture.summaries().map(\.id) == [second, third])

    // 남은 둘이 모두 받는 중이면 상한을 넘어도 지우지 않는다.
    let (fourth, _) = try await fixture.launched(apps[3], run: 3)
    #expect(await fixture.summaries().map(\.id) == [second, third, fourth])
  }

  @Test("다른 기기의 세션은 상한에 세지 않는다")
  func limitIsPerDevice() async throws {
    let fixture = AppLogFixture(limits: AppLogLimits(maxLines: 100, maxBytes: 1000, sessionsPerDevice: 1))
    let (first, firstRun) = try await fixture.launched(run: 0)
    firstRun.finish(.success(.exited))
    _ = try await fixture.waitForEnd(of: first)

    let (second, _) = try await fixture.launched(on: SampleID.iPhoneOff, run: 1)

    #expect(await fixture.summaries().map(\.id) == [first, second])
  }

  private static func snapshot(_ fixture: AppLogFixture, _ id: AppLogSessionID) async throws -> AppLogLineUpdate {
    for await update in await fixture.client.lineUpdates(of: id) {
      return update
    }
    Issue.record("스냅숏이 오지 않았다")
    throw CancellationError()
  }
}
