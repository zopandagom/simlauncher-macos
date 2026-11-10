import Foundation
import ScreenLayoutInterface
import Synchronization
import Testing
@testable import ScreenLayoutImpl

struct KeyedSerialQueueTests {
  /// 테스트가 여는 문. 기다리는 body 는 취소되면 `.cancelled` 를 던진다 (`runCancellable` 흉내).
  final class Gate: Sendable {
    private let opened = Mutex(false)

    func open() {
      self.opened.withLock { $0 = true }
    }

    func wait() async throws(ScreenLayoutError) {
      while !self.opened.withLock({ $0 }) {
        if Task.isCancelled {
          throw .cancelled
        }
        try? await Task.sleep(for: .milliseconds(5))
      }
    }
  }

  /// body 에서 일어난 일, 순서대로.
  final class Log: Sendable {
    private let entries = Mutex<[String]>([])

    func add(_ entry: String) {
      self.entries.withLock { $0.append(entry) }
    }

    var all: [String] {
      self.entries.withLock { $0 }
    }

    func contains(_ entry: String) -> Bool {
      self.all.contains(entry)
    }
  }

  static let first = "First"
  static let second = "Second"

  /// `name` 시작을 적고 문을 기다린 뒤 끝을 적고 `name` 을 돌려준다.
  static func run(
    _ queue: KeyedSerialQueue<String>,
    _ id: String,
    _ name: String,
    gate: Gate?,
    log: Log,
    failure: ScreenLayoutError? = nil
  ) -> Task<Result<String, ScreenLayoutError>, Never> {
    Task {
      do throws(ScreenLayoutError) {
        let value = try await queue.run(id) { () async throws(ScreenLayoutError) -> String in
          log.add("start \(name)")
          try await gate?.wait()
          if let failure {
            log.add("fail \(name)")
            throw failure
          }
          log.add("end \(name)")
          return name
        }
        return .success(value)
      } catch {
        return .failure(error)
      }
    }
  }

  /// 차례에 `count` 번째 호출까지 들어올 때까지 기다린다.
  static func waitForRuns(_ queue: KeyedSerialQueue<String>, _ count: Int) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while await queue.runCount < count {
      guard ContinuousClock.now < deadline else {
        Issue.record("차례에 들어오지 않았다")
        return
      }
      try await Task.sleep(for: .milliseconds(5))
    }
  }

  @Test("같은 키의 두 호출은 앞 body 가 끝난 뒤에 뒤 body 가 시작한다")
  func serializesSameDevice() async throws {
    let queue = KeyedSerialQueue<String>()
    let log = Log()
    let gate = Gate()
    let firstRun = Self.run(queue, Self.first, "a", gate: gate, log: log)
    #expect(try await waitUntil { log.contains("start a") })
    let secondRun = Self.run(queue, Self.first, "b", gate: nil, log: log)
    try await Self.waitForRuns(queue, 2)
    try await Task.sleep(for: .milliseconds(50))
    #expect(!log.contains("start b"))

    gate.open()

    #expect(await firstRun.value == .success("a"))
    #expect(await secondRun.value == .success("b"))
    #expect(log.all == ["start a", "end a", "start b", "end b"])
    #expect(await queue.pendingKeyCount == 0)
  }

  @Test("다른 키는 서로 기다리지 않는다")
  func otherDevicesOverlap() async throws {
    let queue = KeyedSerialQueue<String>()
    let log = Log()
    let gate = Gate()
    let firstRun = Self.run(queue, Self.first, "a", gate: gate, log: log)
    #expect(try await waitUntil { log.contains("start a") })

    let secondRun = Self.run(queue, Self.second, "b", gate: nil, log: log)

    #expect(await secondRun.value == .success("b"))
    #expect(!log.contains("end a"))
    gate.open()
    #expect(await firstRun.value == .success("a"))
  }

  @Test("기다리는 중 취소된 호출은 앞 호출이 끝난 뒤 body 없이 cancelled, 그 뒤 호출은 진행한다")
  func cancelWhileWaiting() async throws {
    let queue = KeyedSerialQueue<String>()
    let log = Log()
    let gate = Gate()
    let firstRun = Self.run(queue, Self.first, "a", gate: gate, log: log)
    #expect(try await waitUntil { log.contains("start a") })
    let secondRun = Self.run(queue, Self.first, "b", gate: nil, log: log)
    try await Self.waitForRuns(queue, 2)

    secondRun.cancel()
    let thirdRun = Self.run(queue, Self.first, "c", gate: nil, log: log)
    try await Self.waitForRuns(queue, 3)
    try await Task.sleep(for: .milliseconds(50))
    #expect(!log.contains("start c"))
    gate.open()

    #expect(await firstRun.value == .success("a"))
    #expect(await secondRun.value == .failure(.cancelled))
    #expect(await thirdRun.value == .success("c"))
    #expect(!log.contains("start b"))
    #expect(log.all == ["start a", "end a", "start c", "end c"])
    #expect(await queue.pendingKeyCount == 0)
  }

  @Test("실행 중인 body 를 취소하면 body 가 취소를 받고 다음 호출이 진행한다")
  func cancelRunningBody() async throws {
    let queue = KeyedSerialQueue<String>()
    let log = Log()
    let firstRun = Self.run(queue, Self.first, "a", gate: Gate(), log: log)
    #expect(try await waitUntil { log.contains("start a") })
    let secondRun = Self.run(queue, Self.first, "b", gate: nil, log: log)
    try await Self.waitForRuns(queue, 2)

    firstRun.cancel()

    #expect(await firstRun.value == .failure(.cancelled))
    #expect(await secondRun.value == .success("b"))
    #expect(!log.contains("end a"))
  }

  @Test("앞 호출이 실패해도 다음 호출은 진행한다")
  func failureDoesNotBlock() async throws {
    let queue = KeyedSerialQueue<String>()
    let log = Log()
    let gate = Gate()
    let firstRun = Self.run(queue, Self.first, "a", gate: gate, log: log, failure: .unreadable)
    #expect(try await waitUntil { log.contains("start a") })
    let secondRun = Self.run(queue, Self.first, "b", gate: nil, log: log)
    try await Self.waitForRuns(queue, 2)
    gate.open()

    #expect(await firstRun.value == .failure(.unreadable))
    #expect(await secondRun.value == .success("b"))
    #expect(log.all == ["start a", "fail a", "start b", "end b"])
  }

  @Test("이미 취소된 Task 의 호출은 body 없이 cancelled 이고 차례를 남기지 않는다")
  func alreadyCancelled() async {
    let queue = KeyedSerialQueue<String>()
    let log = Log()
    let task = Task { () async -> Result<String, ScreenLayoutError> in
      // 취소되면 곧바로 깨어난다. 어느 쪽이든 run 에 들어갈 때 이 Task 는 취소된 상태다.
      try? await Task.sleep(for: .seconds(10))
      do throws(ScreenLayoutError) {
        return try await .success(queue.run(Self.first) { () async throws(ScreenLayoutError) -> String in
          log.add("start late")
          return "late"
        })
      } catch {
        return .failure(error)
      }
    }
    task.cancel()

    #expect(await task.value == .failure(.cancelled))
    #expect(!log.contains("start late"))
    #expect(await queue.pendingKeyCount == 0)
  }
}
