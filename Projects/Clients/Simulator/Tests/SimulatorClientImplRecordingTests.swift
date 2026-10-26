import CommandInterface
import CommandTesting
import Core
import Foundation
import SimulatorInterface
import Synchronization
import Testing
@testable import SimulatorImpl

/// recordVideo 의 인자·환경·사전 확인·시작 신호·결과 판정. 목록은 `simctl-list` 픽스처다 (…0001 켜짐, …0002 꺼짐).
/// 녹화 명령은 `runCancellable` 처리기로 흉내 낸다: Task 취소로 멈춘 것은 처리기가 `.cancelled` 를 던지는 것으로 본다.
struct SimulatorClientImplRecordingTests {
  private static let list = ["simctl", "list", "-j"]
  private static let booted = VirtualDevice.ID("00000000-0000-0000-0000-000000000001")
  private static let shutdown = VirtualDevice.ID("00000000-0000-0000-0000-000000000002")
  private static let missing = VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF")
  private static let developer = URL(filePath: "/X/Xcode.app/Contents/Developer", directoryHint: .isDirectory)
  private static let file = URL(filePath: "/M/SimLauncher/iPhone 17 (iOS 27.0) 2026-10-26 13.41.00.mov")
  private static let note = "Note: No display specified. Defaulting to display: 11111111-2222-3333-4444-555555555555 "
    + "(screenID: 1, name: LCD)\n"

  @Test("UDID 형식이 아니면 provider·프로세스 없이 deviceNotFound", arguments: ["", "-h", "iPhone 17", "booted"])
  func invalidUDID(raw: String) async throws {
    let command = try Self.command(recording: Self.stopped(signal: true))
    let counter = ProviderCounter(returning: Self.developer)

    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.client(command, provider: counter).recordVideo(on: VirtualDevice.ID(raw), to: Self.file) {}
    }
    #expect(command.invocations.isEmpty)
    #expect(counter.calls == 0)
  }

  @Test("파일 URL 이 아니면 provider·프로세스 없이 commandFailed")
  func notFileURL() async throws {
    let command = try Self.command(recording: Self.stopped(signal: true))
    let counter = ProviderCounter(returning: Self.developer)

    await #expect(throws: SimulatorError.commandFailed) {
      try await Self.client(command, provider: counter)
        .recordVideo(on: Self.booted, to: #require(URL(string: "https://example.com/a.mov"))) {}
    }
    #expect(command.invocations.isEmpty)
    #expect(counter.calls == 0)
  }

  @Test("provider 가 nil 이면 아무것도 실행하지 않고 developerToolsUnavailable")
  func noXcode() async throws {
    let command = try Self.command(recording: Self.stopped(signal: true))
    let counter = ProviderCounter(returning: nil)

    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(command, provider: counter).recordVideo(on: Self.booted, to: Self.file) {}
    }
    #expect(command.invocations.isEmpty)
    #expect(counter.calls == 1)
  }

  @Test("목록에 없는 기기는 목록만 읽고 runCancellable 을 부르지 않고 deviceNotFound")
  func missingDevice() async throws {
    let command = try Self.command(recording: Self.stopped(signal: true))

    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.client(command).recordVideo(on: Self.missing, to: Self.file) {}
    }
    #expect(command.invocations.map(\.arguments) == [Self.list])
  }

  @Test("꺼진 기기는 목록만 읽고 runCancellable 을 부르지 않고 deviceNotBooted")
  func notBooted() async throws {
    let command = try Self.command(recording: Self.stopped(signal: true))

    await #expect(throws: SimulatorError.deviceNotBooted) {
      try await Self.client(command).recordVideo(on: Self.shutdown, to: Self.file) {}
    }
    #expect(command.invocations.map(\.arguments) == [Self.list])
    #expect(command.invocations.allSatisfy { !$0.isCancellable })
  }

  @Test("켜진 기기는 목록 뒤에 대문자 UDID·표준화한 경로로 녹화하고, 같은 DEVELOPER_DIR·시간 제한 없이 runCancellable 을 쓴다")
  func arguments() async throws {
    let command = try Self.command(recording: Self.stopped(signal: true))
    let counter = ProviderCounter(returning: Self.developer)
    let messy = URL(filePath: "/M/SimLauncher/../SimLauncher/a b.mov")

    _ = try await Self.client(command, provider: counter, fileSize: 10)
      .recordVideo(on: VirtualDevice.ID(Self.booted.rawValue.lowercased()), to: messy) {}

    #expect(command.invocations.map(\.arguments) == [
      Self.list,
      [
        "simctl", "io", Self.booted.rawValue, "recordVideo", "--codec=h264", "--mask=ignored", "--force",
        "/M/SimLauncher/a b.mov",
      ],
    ])
    #expect(command.invocations.map(\.executable) == [SimctlCommand.xcrun, SimctlCommand.xcrun])
    #expect(command.invocations.map { $0.environment["DEVELOPER_DIR"] } == [
      "/X/Xcode.app/Contents/Developer/", "/X/Xcode.app/Contents/Developer/",
    ])
    #expect(command.invocations.map(\.isCancellable) == [false, true])
    #expect(command.invocations.last?.timeout == nil)
    #expect(counter.calls == 1)
  }

  @Test("신호 조각을 넘기면 onStarted 가 한 번 불리고, stdout 의 같은 글자나 두 번째 신호로는 다시 불리지 않는다")
  func onStartedOnce() async throws {
    let command = try Self.command { _, emit throws(CommandError) in
      await emit(.stdout(Data("Recording started\n".utf8)))
      await emit(.stderr(Data((Self.note + "Recording sta").utf8)))
      await emit(.stderr(Data("rted\n".utf8)))
      await emit(.stderr(Data("Recording started\n".utf8)))
      throw .cancelled
    }
    let calls = Mutex(0)

    let result = try await Self.client(command, fileSize: 10).recordVideo(on: Self.booted, to: Self.file) {
      calls.withLock { $0 += 1 }
    }

    #expect(result == .saved)
    #expect(calls.withLock { $0 } == 1)
  }

  @Test("onStarted 가 끝난 뒤에 멈춤 결과를 판정한다")
  func onStartedBeforeOutcome() async throws {
    let order = Mutex<[String]>([])
    let command = try Self.command { _, emit throws(CommandError) in
      await emit(.stderr(Data("Recording started\n".utf8)))
      order.withLock { $0.append("멈춤") }
      throw .cancelled
    }

    _ = try await Self.client(command, fileSize: 10).recordVideo(on: Self.booted, to: Self.file) {
      order.withLock { $0.append("시작") }
    }

    #expect(order.withLock { $0 } == ["시작", "멈춤"])
  }

  @Test("신호 뒤 Task 를 취소해 멈추면 크기 > 0 은 saved")
  func stoppedWithContent() async throws {
    let command = try Self.command(recording: Self.stopped(signal: true))

    let result = try await Self.client(command, fileSize: 125_000).recordVideo(on: Self.booted, to: Self.file) {}

    #expect(result == .saved)
  }

  @Test("신호 뒤 멈췄는데 파일이 비었거나 없으면 recordingUnfinished", arguments: [0, nil] as [Int?])
  func stoppedEmptyAfterStart(size: Int?) async throws {
    let command = try Self.command(recording: Self.stopped(signal: true))

    await #expect(throws: SimulatorError.recordingUnfinished) {
      try await Self.client(command, fileSize: size).recordVideo(on: Self.booted, to: Self.file) {}
    }
  }

  @Test("신호 전에 멈추고 파일이 비었으면 stoppedBeforeStart")
  func stoppedBeforeSignal() async throws {
    let command = try Self.command(recording: Self.stopped(signal: false))

    let result = try await Self.client(command, fileSize: 0).recordVideo(on: Self.booted, to: Self.file) {}

    #expect(result == .stoppedBeforeStart)
  }

  @Test("시작 전에 이미 취소됐으면 목록 확인은 끝까지 하고 녹화는 실행하지 않고 stoppedBeforeStart, onStarted 도 없다")
  func cancelledBeforeStart() async throws {
    let started = Mutex(false)
    let command = try Self.command { _, _ throws(CommandError) in
      Issue.record("처리기를 부르지 않아야 한다")
      throw .cancelled
    }
    let client = Self.client(command, fileSize: nil)

    let task = Task {
      while !Task.isCancelled {
        await Task.yield()
      }
      return try await client.recordVideo(on: Self.booted, to: Self.file) { started.withLock { $0 = true } }
    }
    task.cancel()

    #expect(try await task.value == .stoppedBeforeStart)
    #expect(command.invocations.map(\.isCancellable) == [false, true])
    #expect(!started.withLock { $0 })
  }

  @Test("스스로 exit 0 으로 끝났는데 파일이 비었으면 recordingEmpty")
  func exitedEmpty() async throws {
    let command = try Self.command(recording: Self.exited(.success()))

    await #expect(throws: SimulatorError.recordingEmpty) {
      try await Self.client(command, fileSize: 0).recordVideo(on: Self.booted, to: Self.file) {}
    }
  }

  @Test("스스로 exit 0 으로 끝나고 내용이 있으면 saved")
  func exitedWithContent() async throws {
    let command = try Self.command(recording: Self.exited(.success()))

    let result = try await Self.client(command, fileSize: 1).recordVideo(on: Self.booted, to: Self.file) {}

    #expect(result == .saved)
  }

  @Test("스스로 0 이 아닌 코드로 끝났어도 내용이 있으면 savedAfterFailure")
  func exitedFailureWithContent() async throws {
    let command = try Self.command(recording: Self.exited(.failure(1, "")))

    let result = try await Self.client(command, fileSize: 4096).recordVideo(on: Self.booted, to: Self.file) {}

    #expect(result == .savedAfterFailure)
  }

  @Test("exit 16 원문이고 파일이 없으면 recordingInProgress, 재조회하지 않는다")
  func recordingInProgress() async throws {
    let stderr = Self.note
      + "Error starting video recorder: Error Domain=NSPOSIXErrorDomain Code=16 \"Resource busy\" "
      + "UserInfo={NSLocalizedFailureReason=Host recording is already in progress}.\n"
      + "An error was encountered processing the command (domain=NSPOSIXErrorDomain, code=16):\n"
      + "The operation couldn’t be completed. Host recording is already in progress\n"
      + "Host recording is already in progress\n"
    let command = try Self.command(recording: Self.exited(.failure(16, stderr)))

    await #expect(throws: SimulatorError.recordingInProgress) {
      try await Self.client(command, fileSize: nil).recordVideo(on: Self.booted, to: Self.file) {}
    }
    #expect(command.invocations.count == 2)
  }

  @Test("녹화 프로세스를 시작하지 못하면 developerToolsUnavailable")
  func launchFailure() async throws {
    let command = try Self.command { _, _ throws(CommandError) in
      throw .launchFailed
    }

    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(command, fileSize: nil).recordVideo(on: Self.booted, to: Self.file) {}
    }
  }

  @Test("파일 크기는 녹화가 끝난 뒤 받은 파일 URL 로 읽는다")
  func readsSizeOfFile() async throws {
    let asked = Mutex<[URL]>([])
    let command = try Self.command(recording: Self.stopped(signal: true))
    let client = SimulatorClientImpl(
      developerDirectory: nil,
      command: command,
      fileExists: { _ in false },
      fileSize: { url in
        asked.withLock { $0.append(url) }
        return 1
      },
      baseEnvironment: [:]
    )

    _ = try await client.recordVideo(on: Self.booted, to: Self.file) {}

    #expect(asked.withLock { $0 } == [Self.file])
  }

  // MARK: - 도우미

  /// 신호(선택)를 넘긴 뒤 Task 취소로 멈춘 녹화.
  private static func stopped(signal: Bool) -> CommandClientFake.CancellableHandler {
    { _, emit throws(CommandError) in
      await emit(.stderr(Data(Self.note.utf8)))
      if signal {
        await emit(.stderr(Data("Recording started\n".utf8)))
      }
      throw .cancelled
    }
  }

  /// 스스로 끝난 녹화.
  private static func exited(_ result: CommandResult) -> CommandClientFake.CancellableHandler {
    { _, _ throws(CommandError) in result }
  }

  /// 목록은 `run` 으로 픽스처, 녹화는 `runCancellable` 처리기로 답한다.
  private static func command(
    recording: @escaping CommandClientFake.CancellableHandler
  ) throws -> CommandClientFake {
    let fixture = try Fixture.data("simctl-list")
    return CommandClientFake(
      handler: { invocation throws(CommandError) in
        guard invocation.arguments == Self.list else {
          Issue.record("녹화는 run 으로 부르지 않아야 한다")
          throw .launchFailed
        }
        return .success(fixture)
      },
      cancellableHandler: recording
    )
  }

  private static func client(
    _ command: CommandClientFake,
    provider: ProviderCounter? = nil,
    fileSize: Int? = nil
  ) -> SimulatorClientImpl {
    SimulatorClientImpl(
      developerDirectory: provider.map { counter in { @Sendable in counter.provide() } },
      command: command,
      fileExists: { _ in false },
      fileSize: { _ in fileSize },
      baseEnvironment: [:]
    )
  }
}
