import CommandInterface
import CommandTesting
import Core
import Foundation
import SimulatorInterface
import Synchronization
import Testing
@testable import SimulatorImpl

/// launchWithConsole 의 인자·환경·알림 순서·끝 판정. 실행은 `streamCancellable` 처리기로 흉내 낸다
/// (Task 취소로 멈춘 것은 처리기가 `.cancelled` 를 던지는 것으로 본다).
struct SimulatorClientImplConsoleTests {
  private static let device = VirtualDevice.ID("00000000-0000-0000-0000-000000000001")
  private static let bundleID = AppBundleID("dev.simlauncher.logprobe")!
  private static let developer = URL(filePath: "/X/Xcode.app/Contents/Developer")
  private static let signal = "dev.simlauncher.logprobe: 90395\n"
  static let notInstalled = "An error was encountered processing the command "
    + "(domain=FBSOpenApplicationServiceErrorDomain, code=4):\n"
    + "Simulator device failed to launch dev.simlauncher.logprobe.\n"
  static let shutdown = "An error was encountered processing the command "
    + "(domain=com.apple.CoreSimulator.SimError, code=405):\nUnable to lookup in current state: Shutdown\n"

  /// 받은 알림 기록.
  private final class Events: Sendable {
    private let recorded = Mutex<[AppConsoleEvent]>([])

    var all: [AppConsoleEvent] {
      self.recorded.withLock { $0 }
    }

    func append(_ event: AppConsoleEvent) {
      self.recorded.withLock { $0.append(event) }
    }
  }

  @Test("신호 줄 뒤 앱 줄을 조각마다 넘기고 .exited. 인자·콘솔 환경·isStream 으로 실행한다")
  func success() async throws {
    let command = Self.command { emit throws(CommandError) in
      await emit(.stdout(Data(Self.signal.utf8)))
      await emit(.stderr(Data("ignored\n".utf8)))
      await emit(.stdout(Data("tick 1\r\ntick".utf8)))
      await emit(.stdout(Data(" 2\r\n\n".utf8)))
      return CommandResult(exitCode: 0, stdout: Data(), stderr: Data())
    }
    let events = Events()

    let end = try await Self.client(command).launchWithConsole(Self.bundleID, on: Self.device) { events.append($0) }

    #expect(end == .exited)
    #expect(events.all == [.launched, .lines(["tick 1"]), .lines(["tick 2"])])
    let invocation = try #require(command.invocations.first)
    #expect(command.invocations.count == 1)
    #expect(invocation.executable == SimctlCommand.xcrun)
    #expect(invocation.arguments == [
      "simctl", "launch", "--console-pty", "--terminate-running-process",
      "00000000-0000-0000-0000-000000000001", "dev.simlauncher.logprobe",
    ])
    #expect(invocation.environment == [
      "DEVELOPER_DIR": "/X/Xcode.app/Contents/Developer",
      "NSUnbufferedIO": "YES",
      "SIMCTL_CHILD_OS_ACTIVITY_DT_MODE": "enable",
    ])
    #expect(invocation.isStream)
    #expect(invocation.timeout == nil)
  }

  @Test("소문자 UDID 는 대문자로 넘긴다")
  func uppercasesUDID() async throws {
    let command = Self.command { _ throws(CommandError) in CommandResult(exitCode: 0, stdout: Data(), stderr: Data()) }

    _ = try await Self.client(command)
      .launchWithConsole(Self.bundleID, on: VirtualDevice.ID("abcdefab-0000-0000-0000-000000000001")) { _ in }

    #expect(command.invocations.first?.arguments.dropLast().last == "ABCDEFAB-0000-0000-0000-000000000001")
  }

  @Test(
    "신호 전 0 이 아닌 종료는 launch 와 같은 분류로 던지고 알림이 없다",
    arguments: [
      (Int32(4), SimulatorClientImplConsoleTests.notInstalled, SimulatorError.appNotInstalled),
      (Int32(149), SimulatorClientImplConsoleTests.shutdown, SimulatorError.deviceNotBooted),
    ]
  )
  func failureBeforeSignal(exitCode: Int32, stderr: String, expected: SimulatorError) async {
    let command = Self.command { _ throws(CommandError) in
      CommandResult(exitCode: exitCode, stdout: Data(), stderr: Data(stderr.utf8))
    }
    let events = Events()

    await #expect(throws: expected) {
      try await Self.client(command).launchWithConsole(Self.bundleID, on: Self.device) { events.append($0) }
    }
    #expect(events.all.isEmpty)
  }

  @Test("신호 없이 0 으로 끝나면 .exited 이고 .launched 는 없다")
  func exitZeroWithoutSignal() async throws {
    let command = Self.command { _ throws(CommandError) in CommandResult(exitCode: 0, stdout: Data(), stderr: Data()) }
    let events = Events()

    let end = try await Self.client(command).launchWithConsole(Self.bundleID, on: Self.device) { events.append($0) }

    #expect(end == .exited)
    #expect(events.all.isEmpty)
  }

  @Test("신호 뒤에는 0 이 아닌 종료도 .exited, 남은 조각은 끝에 한 줄로 넘긴다")
  func nonZeroAfterSignal() async throws {
    let command = Self.command { emit throws(CommandError) in
      await emit(.stdout(Data("\(Self.signal)partial".utf8)))
      return CommandResult(exitCode: 1, stdout: Data(), stderr: Data(Self.shutdown.utf8))
    }
    let events = Events()

    let end = try await Self.client(command).launchWithConsole(Self.bundleID, on: Self.device) { events.append($0) }

    #expect(end == .exited)
    #expect(events.all == [.launched, .lines(["partial"])])
  }

  @Test("앱 줄이 신호보다 먼저 와도 성공 (첫 앱 줄에서 .launched)")
  func appLineFirst() async throws {
    let command = Self.command { emit throws(CommandError) in
      await emit(.stdout(Data("probe start\r\n".utf8)))
      await emit(.stdout(Data(Self.signal.utf8)))
      return CommandResult(exitCode: 0, stdout: Data(), stderr: Data())
    }
    let events = Events()

    _ = try await Self.client(command).launchWithConsole(Self.bundleID, on: Self.device) { events.append($0) }

    #expect(events.all == [.launched, .lines(["probe start"])])
  }

  @Test("취소로 멈추면 .stopped")
  func stopped() async throws {
    let command = Self.command { emit throws(CommandError) in
      await emit(.stdout(Data(Self.signal.utf8)))
      throw .cancelled
    }
    let events = Events()

    let end = try await Self.client(command).launchWithConsole(Self.bundleID, on: Self.device) { events.append($0) }

    #expect(end == .stopped)
    #expect(events.all == [.launched])
  }

  @Test("띄우지 못하면 developerToolsUnavailable")
  func launchFailed() async {
    let command = Self.command { _ throws(CommandError) in throw .launchFailed }

    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(command).launchWithConsole(Self.bundleID, on: Self.device) { _ in }
    }
  }

  @Test("UDID 형식이 아니면 provider·프로세스 없이 deviceNotFound", arguments: ["", "-h", "booted"])
  func invalidUDID(raw: String) async {
    let command = Self.command { _ throws(CommandError) in CommandResult(exitCode: 0, stdout: Data(), stderr: Data()) }
    let counter = ProviderCounter(returning: Self.developer)

    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.client(command, provider: counter)
        .launchWithConsole(Self.bundleID, on: VirtualDevice.ID(raw)) { _ in }
    }
    #expect(command.invocations.isEmpty)
    #expect(counter.calls == 0)
  }

  @Test("provider 가 nil 이면 아무것도 실행하지 않고 developerToolsUnavailable")
  func noXcode() async {
    let command = Self.command { _ throws(CommandError) in CommandResult(exitCode: 0, stdout: Data(), stderr: Data()) }
    let counter = ProviderCounter(returning: nil)

    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(command, provider: counter).launchWithConsole(Self.bundleID, on: Self.device) { _ in }
    }
    #expect(command.invocations.isEmpty)
  }

  /// 실행은 `streamCancellable` 처리기로만 답한다.
  private static func command(
    _ console: @escaping @Sendable (_ emit: @Sendable (CommandOutput) async -> Void) async throws(CommandError)
      -> CommandResult
  ) -> CommandClientFake {
    CommandClientFake(
      handler: { _ throws(CommandError) in
        Issue.record("콘솔 실행은 run 으로 부르지 않아야 한다")
        throw .launchFailed
      },
      cancellableHandler: { invocation, emit throws(CommandError) in
        #expect(invocation.isStream)
        return try await console(emit)
      }
    )
  }

  private static func client(_ command: CommandClientFake, provider: ProviderCounter? = nil) -> SimulatorClientImpl {
    let counter = provider ?? ProviderCounter(returning: Self.developer)
    return SimulatorClientImpl(
      developerDirectory: { @Sendable in counter.provide() },
      command: command,
      fileExists: { _ in false },
      baseEnvironment: [:]
    )
  }
}
