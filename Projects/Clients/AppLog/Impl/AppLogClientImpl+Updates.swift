import AppLogInterface
import Foundation

// MARK: - 알림 (세션 요약·줄 구독, 묶음 보내기)

extension AppLogClientImpl {
  public func sessionUpdates() -> AsyncStream<[AppLogSessionSummary]> {
    // 알림마다 전체 목록이라 받는 쪽이 늦으면 가장 새 것 하나만 남긴다.
    let (stream, continuation) = AsyncStream<[AppLogSessionSummary]>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let token = UUID()
    continuation.yield(self.table.publishedSummaries)
    self.sessionSubscribers[token] = continuation
    continuation.onTermination = { _ in
      Task { await self.removeSessionSubscriber(token) }
    }
    return stream
  }

  public func lineUpdates(of session: AppLogSessionID) -> AsyncStream<AppLogLineUpdate> {
    let (stream, continuation) = AsyncStream<AppLogLineUpdate>.makeStream()
    guard let record = self.table.record(session), record.isPublished else {
      continuation.finish()
      return stream
    }
    let token = UUID()
    continuation.yield(
      AppLogLineUpdate(isSnapshot: true, lines: record.buffer.snapshot(), droppedCount: record.buffer.droppedCount)
    )
    self.lineSubscribers[session, default: [:]][token] = LineSubscriber(
      continuation: continuation,
      deliveredThrough: record.buffer.lastIndex
    )
    continuation.onTermination = { _ in
      Task { await self.removeLineSubscriber(token, of: session) }
    }
    return stream
  }

  private func removeSessionSubscriber(_ token: UUID) {
    self.sessionSubscribers[token] = nil
  }

  private func removeLineSubscriber(_ token: UUID, of session: AppLogSessionID) {
    self.lineSubscribers[session]?[token] = nil
    if self.lineSubscribers[session]?.isEmpty == true {
      self.lineSubscribers[session] = nil
    }
  }

  func broadcastSessions() {
    let summaries = self.table.publishedSummaries
    for subscriber in self.sessionSubscribers.values {
      subscriber.yield(summaries)
    }
  }

  /// 구독자가 있으면 `flushInterval` 뒤 한 번 보내도록 예약한다 (`.zero` 면 곧바로).
  func scheduleFlush(_ id: AppLogSessionID) {
    guard self.lineSubscribers[id] != nil else { return }
    guard self.flushInterval > .zero else {
      self.flush(id)
      return
    }
    guard self.flushTasks[id] == nil else { return }
    let interval = self.flushInterval
    self.flushTasks[id] = Task {
      try? await Task.sleep(for: interval)
      guard !Task.isCancelled else { return }
      await self.scheduledFlush(id)
    }
  }

  private func scheduledFlush(_ id: AppLogSessionID) {
    self.flushTasks[id] = nil
    self.flush(id)
  }

  /// 구독자마다 보낸 번호 뒤의 줄만 보낸다 (버린 줄은 빠진다).
  func flush(_ id: AppLogSessionID) {
    guard let record = self.table.record(id), var subscribers = self.lineSubscribers[id] else { return }
    let buffer = record.buffer
    for (token, subscriber) in subscribers {
      let lines = buffer.lines(after: subscriber.deliveredThrough)
      guard !lines.isEmpty else { continue }
      subscriber.continuation.yield(
        AppLogLineUpdate(isSnapshot: false, lines: lines, droppedCount: buffer.droppedCount)
      )
      subscribers[token]?.deliveredThrough = buffer.lastIndex
    }
    self.lineSubscribers[id] = subscribers
  }

  func finishLineSubscribers(of id: AppLogSessionID) {
    self.flushTasks.removeValue(forKey: id)?.cancel()
    let subscribers = self.lineSubscribers.removeValue(forKey: id) ?? [:]
    for subscriber in subscribers.values {
      subscriber.continuation.finish()
    }
  }
}
