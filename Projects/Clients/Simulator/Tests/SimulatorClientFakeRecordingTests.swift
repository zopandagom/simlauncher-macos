import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Synchronization
import Testing

struct SimulatorClientFakeRecordingTests {
  private static let file = URL(filePath: "/SimLauncher-Fake-Movies/a.mov")
  private static let missing = VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF")

  @Test("기본은 시작 신호 뒤 취소될 때까지 기다리고, 취소하면 saved. 목록은 바꾸지 않는다")
  func defaultRecording() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    let started = Mutex(false)
    let task = Task {
      try await fake.recordVideo(on: SampleID.iPhoneOn, to: Self.file) { started.withLock { $0 = true } }
    }
    while !started.withLock({ $0 }) {
      await Task.yield()
    }

    task.cancel()

    #expect(try await task.value == .saved)
    #expect(fake.calls == [.recordVideo(SampleID.iPhoneOn, Self.file)])
    #expect(try await fake.fetchInventory() == .sample)
  }

  @Test("시작 에러를 설정하면 신호 없이 던지고, 꺼진 기기는 deviceNotBooted, 목록에 없으면 deviceNotFound")
  func startErrors() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    let started = Mutex(false)

    await #expect(throws: SimulatorError.deviceNotBooted) {
      try await fake.recordVideo(on: SampleID.iPhoneOff, to: Self.file) { started.withLock { $0 = true } }
    }
    await #expect(throws: SimulatorError.deviceNotFound) {
      try await fake.recordVideo(on: Self.missing, to: Self.file) { started.withLock { $0 = true } }
    }
    fake.setRecordingStartError(.recordingInProgress)
    await #expect(throws: SimulatorError.recordingInProgress) {
      try await fake.recordVideo(on: SampleID.iPhoneOn, to: Self.file) { started.withLock { $0 = true } }
    }
    #expect(!started.withLock { $0 })
    #expect(fake.calls == [
      .recordVideo(SampleID.iPhoneOff, Self.file),
      .recordVideo(Self.missing, Self.file),
      .recordVideo(SampleID.iPhoneOn, Self.file),
    ])
  }

  @Test("신호를 보내지 않게 설정하면 onStarted 없이 기다리다 취소하면 stoppedBeforeStart")
  func noSignal() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.setRecordingSignalsStart(false)
    let started = Mutex(false)
    let task = Task {
      try await fake.recordVideo(on: SampleID.iPhoneOn, to: Self.file) { started.withLock { $0 = true } }
    }
    while fake.calls.isEmpty {
      await Task.yield()
    }

    task.cancel()

    #expect(try await task.value == .stoppedBeforeStart)
    #expect(!started.withLock { $0 })
  }

  @Test("이미 취소된 Task 에서는 신호 없이 바로 stoppedBeforeStart")
  func alreadyCancelled() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    let started = Mutex(false)
    let task = Task {
      while !Task.isCancelled {
        await Task.yield()
      }
      return try await fake.recordVideo(on: SampleID.iPhoneOn, to: Self.file) { started.withLock { $0 = true } }
    }
    task.cancel()

    #expect(try await task.value == .stoppedBeforeStart)
    #expect(!started.withLock { $0 })
  }

  @Test("멈춘 뒤 결과를 설정하면 그 값을 내거나 던진다")
  func stopOutcome() async throws {
    let fake = SimulatorClientFake(inventory: .sample)

    fake.setRecordingStopOutcome(.success(.savedAfterFailure))
    #expect(try await Self.recordAndStop(fake) == .savedAfterFailure)
    fake.setRecordingStopOutcome(.failure(.recordingUnfinished))
    await #expect(throws: SimulatorError.recordingUnfinished) { try await Self.recordAndStop(fake) }
    fake.setRecordingStopOutcome(nil)
    #expect(try await Self.recordAndStop(fake) == .saved)
  }

  @Test("멈춘 recordVideo 는 기록된 뒤 resume 까지 시작 신호를 보내지 않는다")
  func suspendRecordings() async throws {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.suspendRecordings()
    let started = Mutex(false)
    let task = Task {
      try await fake.recordVideo(on: SampleID.iPhoneOn, to: Self.file) { started.withLock { $0 = true } }
    }
    while fake.calls.isEmpty {
      await Task.yield()
    }
    #expect(!started.withLock { $0 })

    fake.resumeRecordings()
    while !started.withLock({ $0 }) {
      await Task.yield()
    }
    task.cancel()

    #expect(try await task.value == .saved)
  }

  /// 시작 신호를 받으면 바로 취소한다.
  private static func recordAndStop(_ fake: SimulatorClientFake) async throws -> ScreenRecordingResult {
    let started = Mutex(false)
    let task = Task {
      try await fake.recordVideo(on: SampleID.iPhoneOn, to: Self.file) { started.withLock { $0 = true } }
    }
    while !started.withLock({ $0 }) {
      await Task.yield()
    }
    task.cancel()
    return try await task.value
  }
}
