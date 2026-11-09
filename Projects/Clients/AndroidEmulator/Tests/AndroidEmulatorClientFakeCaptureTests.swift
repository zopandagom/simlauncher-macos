import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Synchronization
import Testing

/// Feature 테스트·Example 이 기대는 Fake 의 스크린샷·녹화 동작.
struct AndroidEmulatorClientFakeCaptureTests {
  @Test("스크린샷: 기록하고 설정한 에러를 던진다, 멈춤은 재개까지 기다린다")
  func screenshot() async throws {
    let fake = AndroidEmulatorClientFake(inventory: .sample)
    let tablet = AndroidVirtualDevice.bootedTabletSample.id
    let file = URL(filePath: "/Users/fake/Pictures/SimLauncher/shot.png")

    try await fake.screenshot(on: tablet, to: file)
    fake.setScreenshotError(.captureFailed)
    await #expect(throws: AndroidEmulatorError.captureFailed) { try await fake.screenshot(on: tablet, to: file) }
    fake.setScreenshotError(nil)
    fake.suspendScreenshots()
    let taking = Task { try await fake.screenshot(on: tablet, to: file) }
    while fake.calls.count < 3 {
      await Task.yield()
    }
    fake.resumeScreenshots()
    try await taking.value
    #expect(fake.calls == Array(repeating: .screenshot(tablet, file), count: 3))
  }

  @Test("녹화: 시작 신호 뒤 취소까지 기다려 saved, 멈춘 뒤 결과를 바꿀 수 있다")
  func recordUntilCancelled() async throws {
    let fake = AndroidEmulatorClientFake(inventory: .sample)
    let tablet = AndroidVirtualDevice.bootedTabletSample.id
    let file = URL(filePath: "/Users/fake/Movies/SimLauncher/rec.mp4")
    let started = FakeStartFlag()

    let recording = Task { try await fake.recordScreen(on: tablet, to: file) { started.set() } }
    while !started.isSet {
      await Task.yield()
    }
    recording.cancel()
    #expect(try await recording.value == .saved)

    fake.setRecordingResult(.failure(.recordingLost))
    let lost = Task { try await fake.recordScreen(on: tablet, to: file) {} }
    while fake.calls.count < 2 {
      await Task.yield()
    }
    lost.cancel()
    await #expect(throws: AndroidEmulatorError.recordingLost) { try await lost.value }
    #expect(fake.calls == [.recordScreen(tablet, file), .recordScreen(tablet, file)])
  }

  @Test("녹화: 시작 신호 없이 멈추면 stoppedBeforeStart, 스스로 끝나는 결과는 취소를 기다리지 않는다")
  func recordVariants() async throws {
    let fake = AndroidEmulatorClientFake(inventory: .sample)
    let tablet = AndroidVirtualDevice.bootedTabletSample.id
    let file = URL(filePath: "/Users/fake/Movies/SimLauncher/rec.mp4")
    let started = FakeStartFlag()

    fake.setRecordingSignalsStart(false)
    fake.suspendRecordings()
    let silent = Task { try await fake.recordScreen(on: tablet, to: file) { started.set() } }
    while fake.calls.isEmpty {
      await Task.yield()
    }
    silent.cancel()
    fake.resumeRecordings()
    #expect(try await silent.value == .stoppedBeforeStart)
    #expect(!started.isSet)

    fake.setRecordingSignalsStart(true)
    fake.setRecordingEndsByItself(.success(.savedAtTimeLimit))
    #expect(try await fake.recordScreen(on: tablet, to: file) { started.set() } == .savedAtTimeLimit)
    #expect(started.isSet)

    let failed = FakeStartFlag()
    fake.setRecordingEndsByItself(.failure(.recordingFailed))
    await #expect(throws: AndroidEmulatorError.recordingFailed) {
      _ = try await fake.recordScreen(on: tablet, to: file) { failed.set() }
    }
    #expect(!failed.isSet)
  }
}

/// `onStarted` 를 받았는지.
final class FakeStartFlag: Sendable {
  private let flag = Mutex(false)

  var isSet: Bool {
    self.flag.withLock { $0 }
  }

  func set() {
    self.flag.withLock { $0 = true }
  }
}

/// `launchWithLogcat` 이 넘긴 알림.
final class FakeLogcatEvents: Sendable {
  private let events = Mutex<[AndroidLogcatEvent]>([])

  var all: [AndroidLogcatEvent] {
    self.events.withLock { $0 }
  }

  func append(_ event: AndroidLogcatEvent) {
    self.events.withLock { $0.append(event) }
  }
}
