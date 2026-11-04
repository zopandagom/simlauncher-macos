import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Synchronization
import Testing

struct SimulatorClientFakeConsoleTests {
  private static let bundleID = AppBundleID("com.example.app")!

  @Test("기본은 .launched 를 보내고 취소될 때까지 기다린 뒤 .stopped, 호출을 기록한다")
  func defaultConsole() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    let launched = Mutex(false)
    let task = Task {
      try await fake.launchWithConsole(Self.bundleID, on: SampleID.iPhoneOn) { event in
        if event == .launched {
          launched.withLock { $0 = true }
        }
      }
    }
    while !launched.withLock({ $0 }) {
      await Task.yield()
    }

    task.cancel()

    #expect(try await task.value == .stopped)
    #expect(fake.calls == [.launchWithConsole(Self.bundleID, SampleID.iPhoneOn)])
  }

  @Test("처리기가 없고 launch 에러를 설정하면 알림 없이 던진다")
  func launchError() async {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.setLaunchError(.appNotInstalled)

    await #expect(throws: SimulatorError.appNotInstalled) {
      try await fake.launchWithConsole(Self.bundleID, on: SampleID.iPhoneOn) { _ in Issue.record("알림이 없어야 한다") }
    }
  }

  @Test("처리기가 있으면 그 알림과 끝을 쓴다")
  func handler() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.setConsoleHandler { _, _, emit throws(SimulatorError) in
      await emit(.launched)
      await emit(.lines(["a", "b"]))
      return .exited
    }
    let events = Mutex<[AppConsoleEvent]>([])

    let end = try await fake.launchWithConsole(Self.bundleID, on: SampleID.iPhoneOn) { event in
      events.withLock { $0.append(event) }
    }

    #expect(end == .exited)
    #expect(events.withLock { $0 } == [.launched, .lines(["a", "b"])])
  }
}
