import AppLogInterface
import Foundation
import Testing
@testable import DeviceLogFeature

/// 거르기를 기다리는 동안 "필터에 맞는 줄이 없습니다" 안내와 빈 줄 수를 숨기는 규칙 (`DeviceLogWindow` 값을 직접 몬다).
struct DeviceLogWindowPendingTests {
  private let session = AppLogSessionID(UUID())

  private func lines(_ indices: ClosedRange<Int>, _ text: String = "line") -> [AppLogLine] {
    indices.map { AppLogLine(index: $0, text: "\(text) \($0)") }
  }

  private func snapshot(_ lines: [AppLogLine]) -> AppLogLineUpdate {
    AppLogLineUpdate(isSnapshot: true, lines: lines, droppedCount: 0)
  }

  private func batch(_ lines: [AppLogLine]) -> AppLogLineUpdate {
    AppLogLineUpdate(isSnapshot: false, lines: lines, droppedCount: 0)
  }

  /// 연 창에 세션을 고르고 스냅숏을 넣는다 (거르기 전).
  private func openedWindow(_ lines: [AppLogLine]) -> DeviceLogWindow {
    var window = DeviceLogWindow()
    window.open()
    window.select(self.session)
    window.applySnapshot(self.snapshot(lines))
    return window
  }

  /// 메인 밖 거르기를 한 번 돌려 결과를 적용한다.
  private func run(_ window: inout DeviceLogWindow, isFull: Bool) async throws {
    let job = try #require(window.filterJob(isFull: isFull))
    let result = await CompiledLogFilter.filtered(job.lines, by: job.filter)
    window.applyFilterResult(result, of: job)
  }

  /// 맞는 줄이 없는 필터로 바꾼다.
  private func setNoMatchFilter(_ window: inout DeviceLogWindow) -> Bool {
    window.changeFilter { $0.setText("nothing-matches", of: 0) }
  }

  @Test("스냅숏 뒤 첫 전체 결과 전에는 안내·줄 수를 숨기고, 결과(맞는 줄 0 이어도)가 오면 보인다")
  func snapshotThenFullResult() async throws {
    var window = DeviceLogWindow()
    window.open()
    window.select(self.session)
    #expect(self.setNoMatchFilter(&window))
    window.applySnapshot(self.snapshot(self.lines(0 ... 2)))
    #expect(window.isAwaitingFullFilter)
    #expect(!window.showsNoMatchingNotice)
    #expect(window.hidesLineCounts)
    try await self.run(&window, isFull: true)
    #expect(!window.isAwaitingFullFilter)
    #expect(window.visibleLines.isEmpty)
    #expect(window.showsNoMatchingNotice)
    #expect(!window.hidesLineCounts)
  }

  @Test("필터를 바꾸면 기다리고, 앞 작업의 꼬리 결과로는 풀리지 않으며, 새 전체 결과로 풀린다")
  func filterChangeWaitsForFullResult() async throws {
    var window = self.openedWindow(self.lines(0 ... 1))
    try await self.run(&window, isFull: true)
    let needsFiltering = window.applyBatch(self.batch(self.lines(2 ... 3)))
    #expect(needsFiltering)
    let oldTail = try #require(window.filterJob(isFull: false))
    #expect(self.setNoMatchFilter(&window))
    #expect(window.isAwaitingFullFilter)
    // 앞 결과(줄 있음)가 그대로 보이므로 안내·줄 수는 숨기지 않는다.
    #expect(!window.showsNoMatchingNotice)
    #expect(!window.hidesLineCounts)
    let tailResult = await CompiledLogFilter.filtered(oldTail.lines, by: oldTail.filter)
    window.applyFilterResult(tailResult, of: oldTail)
    #expect(window.isAwaitingFullFilter)
    try await self.run(&window, isFull: true)
    #expect(!window.isAwaitingFullFilter)
    #expect(window.showsNoMatchingNotice)
  }

  @Test("앞 결과가 0줄일 때 필터를 바꾸면 결과가 올 때까지 안내·줄 수를 숨긴다")
  func filterChangeFromEmptyResultHides() async throws {
    var window = self.openedWindow(self.lines(0 ... 1))
    #expect(self.setNoMatchFilter(&window))
    try await self.run(&window, isFull: true)
    #expect(window.showsNoMatchingNotice)
    let changed = window.changeFilter { $0.setText("still-nothing", of: 0) }
    #expect(changed)
    #expect(!window.showsNoMatchingNotice)
    #expect(window.hidesLineCounts)
    try await self.run(&window, isFull: true)
    #expect(window.showsNoMatchingNotice)
    #expect(!window.hidesLineCounts)
  }

  @Test("잘못된 정규식은 다시 거르지 않아 기다림이 그대로다")
  func invalidRegexKeepsWaitState() async throws {
    var window = self.openedWindow(self.lines(0 ... 1))
    let toRegex = window.changeFilter { $0.setKind(.regex, of: 0) }
    #expect(toRegex)
    #expect(self.setNoMatchFilter(&window))
    try await self.run(&window, isFull: true)
    let toInvalid = window.changeFilter { $0.setText("(", of: 0) }
    #expect(!toInvalid)
    #expect(window.filterProblem != nil)
    #expect(!window.isAwaitingFullFilter)
    #expect(window.showsNoMatchingNotice)
  }

  @Test("일시정지 중 필터를 바꾸면 결과로 풀리고, 일시정지 중 들어온 줄은 기다림으로 보지 않는다")
  func pausedFilterChange() async throws {
    var window = self.openedWindow(self.lines(0 ... 1))
    try await self.run(&window, isFull: true)
    window.pause()
    #expect(self.setNoMatchFilter(&window))
    #expect(window.isAwaitingFullFilter)
    #expect(!window.showsNoMatchingNotice)
    try await self.run(&window, isFull: true)
    #expect(!window.isAwaitingFullFilter)
    let needsFiltering = window.applyBatch(self.batch(self.lines(2 ... 3)))
    #expect(!needsFiltering)
    #expect(window.showsNoMatchingNotice)
    #expect(!window.hidesLineCounts)
  }

  @Test("일시정지 중 지운 뒤 줄이 들어오면 안내는 숨기고 줄 수(보이는 0줄)는 보인다")
  func pausedClearThenBatch() async throws {
    var window = self.openedWindow(self.lines(0 ... 1))
    try await self.run(&window, isFull: true)
    window.pause()
    window.clear()
    let needsFiltering = window.applyBatch(self.batch(self.lines(2 ... 3)))
    #expect(!needsFiltering)
    #expect(window.visibleLines.isEmpty)
    #expect(!window.lines.isEmpty)
    #expect(!window.showsNoMatchingNotice)
    #expect(!window.hidesLineCounts)
  }

  @Test("기다리는 중 지우기·닫기·다른 세션 고르기는 기다림을 끝낸다")
  func resetsEndWaiting() {
    var cleared = self.openedWindow(self.lines(0 ... 1))
    #expect(cleared.isAwaitingFullFilter)
    cleared.clear()
    #expect(!cleared.isAwaitingFullFilter)
    #expect(!cleared.hidesLineCounts)

    var closed = self.openedWindow(self.lines(0 ... 1))
    closed.close()
    #expect(!closed.isAwaitingFullFilter)

    var moved = self.openedWindow(self.lines(0 ... 1))
    moved.select(AppLogSessionID(UUID()))
    #expect(!moved.isAwaitingFullFilter)
  }

  @Test("줄 0개 스냅숏은 빈 전체 결과로 풀린다")
  func emptySnapshot() async throws {
    var window = self.openedWindow([])
    #expect(window.isAwaitingFullFilter)
    try await self.run(&window, isFull: true)
    #expect(!window.isAwaitingFullFilter)
    #expect(!window.showsNoMatchingNotice)
    #expect(!window.hidesLineCounts)
  }

  @Test("0줄 스냅숏 뒤 첫 묶음은 꼬리 결과 전까지 안내·줄 수를 숨기고, 결과(맞는 줄 없음)가 오면 보인다")
  func firstBatchAfterEmptySnapshot() async throws {
    var window = self.openedWindow([])
    #expect(self.setNoMatchFilter(&window))
    try await self.run(&window, isFull: true)
    let needsFiltering = window.applyBatch(self.batch(self.lines(0 ... 1)))
    #expect(needsFiltering)
    #expect(!window.showsNoMatchingNotice)
    #expect(window.hidesLineCounts)
    try await self.run(&window, isFull: false)
    #expect(window.showsNoMatchingNotice)
    #expect(!window.hidesLineCounts)
  }

  @Test("거른 줄이 있고 맞는 줄이 없을 때 묶음이 와도 꼬리 결과 전에 안내·줄 수가 그대로 보인다 (깜빡이지 않는다)")
  func batchesDoNotFlicker() async throws {
    var window = self.openedWindow(self.lines(0 ... 1))
    #expect(self.setNoMatchFilter(&window))
    try await self.run(&window, isFull: true)
    let needsFiltering = window.applyBatch(self.batch(self.lines(2 ... 3)))
    #expect(needsFiltering)
    #expect(window.showsNoMatchingNotice)
    #expect(!window.hidesLineCounts)
  }

  @Test("닫힌 창·세션 없는 창에서 필터를 바꾸면 기다리지 않는다")
  func noWaitWithoutJob() {
    var closed = DeviceLogWindow()
    #expect(self.setNoMatchFilter(&closed))
    #expect(!closed.isAwaitingFullFilter)

    var noSession = DeviceLogWindow()
    noSession.open()
    noSession.select(nil)
    #expect(self.setNoMatchFilter(&noSession))
    #expect(!noSession.isAwaitingFullFilter)
  }
}
