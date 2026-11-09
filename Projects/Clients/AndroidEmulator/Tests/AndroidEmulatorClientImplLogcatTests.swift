import AndroidEmulatorInterface
import CommandInterface
import CommandTesting
import Core
import Foundation
import Synchronization
import Testing
@testable import AndroidEmulatorImpl

/// 로그 받기와 함께 하는 앱 실행: 사전 확인 → 화면 찾기 → force-stop → date → am start → pid 기다림 → logcat 받기(또는 uid 한 번 읽기).
/// adb 앱 명령은 `Replies`, 받기(`streamCancellable`)는 `FakeLogcatStream` 이 흉내 낸다.
struct AndroidEmulatorClientImplLogcatTests {
  static let pixel = AndroidVirtualDevice.ID("Pixel")
  static let package = AndroidPackageName("org.videolan.vlc")!
  static let serial = "emulator-5554"

  static func result(_ code: Int32, stdout: String = "", stderr: String = "") -> CommandResult {
    CommandResult(exitCode: code, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8))
  }

  /// launcher 가 둘 이상일 때 `resolve-activity --brief` 출력 (실측).
  static let chooser = Self.result(
    0,
    stdout: "priority=0 preferredOrder=0 match=0x0 specificIndex=-1 isDefault=false\n" +
      "android/com.android.internal.app.ResolverActivity\n"
  )

  /// launcher 둘의 `query-activities --brief` 출력 (실측, 패키지만 바꿨다). 순서는 manifest 순서다.
  static let twoLaunchers = """
  2 activities found:
    Activity #0:
      priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false
      org.videolan.vlc/android.app.Activity
    Activity #1:
      priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false
      org.videolan.vlc/android.app.ListActivity

  """

  static let resolveCall = [
    "-s", "emulator-5554", "shell", "cmd", "package", "resolve-activity", "--brief",
    "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", "org.videolan.vlc",
  ]
  static let forceStopCall = ["-s", "emulator-5554", "shell", "am", "force-stop", "org.videolan.vlc"]
  static let dateCall = ["-s", "emulator-5554", "shell", "date", "+%s.%N"]
  static let startCall = ["-s", "emulator-5554", "shell", "am", "start", "-n", "'org.videolan.vlc/.StartActivity'"]
  static let pidCall = [
    "-s", "emulator-5554", "shell",
    "for i in $(seq 1 60); do p=$(pidof org.videolan.vlc) && { echo $p; exit 0; }; sleep 0.1; done; exit 1",
  ]
  static let uidCall = ["-s", "emulator-5554", "shell", "pm", "list", "packages", "-U", "org.videolan.vlc"]
  static let uidLogCall = [
    "-s", "emulator-5554", "shell", "logcat", "-d", "--uid=10231", "-v", "threadtime", "-T", "1794201687.579",
  ]
  static let streamCall = [
    "-s", "emulator-5554", "shell",
    "( while [ -d /proc/6502 ] && [ -d /proc/$$ ]; do sleep 0.2; done; sleep 1; [ -d /proc/$$ ] && kill $$ ) "
      + "& exec logcat --pid=6502 -v threadtime -T 1794201687.579",
  ]

  /// adb 앱 명령의 답. 기본은 모두 성공하는 실행 (pid 6502, uid 10231).
  struct Replies: Sendable {
    var resolve = AndroidEmulatorClientImplLogcatTests.result(
      0,
      stdout: "priority=0 preferredOrder=0\norg.videolan.vlc/.StartActivity\n"
    )
    var launchers = AndroidEmulatorClientImplLogcatTests.result(1)
    var packagePath = AndroidEmulatorClientImplLogcatTests.result(0)
    var forceStop = AndroidEmulatorClientImplLogcatTests.result(0)
    var date = AndroidEmulatorClientImplLogcatTests.result(0, stdout: "1794201687.579556212\n")
    var start = AndroidEmulatorClientImplLogcatTests.result(
      0,
      stdout: "Starting: Intent { cmp=org.videolan.vlc/.StartActivity }\n"
    )
    var pid: Result<CommandResult, CommandError> = .success(AndroidEmulatorClientImplLogcatTests.result(
      0,
      stdout: "6502\n"
    ))
    var uid = AndroidEmulatorClientImplLogcatTests.result(
      0,
      stdout: "package:org.videolan.vlc.rro uid:10079\npackage:org.videolan.vlc uid:10231\n"
    )
    var uidLog = AndroidEmulatorClientImplLogcatTests.result(1)

    func respond(_ arguments: [String]) throws(CommandError) -> CommandResult {
      let command = Array(arguments.dropFirst(3))
      if command.contains("resolve-activity") {
        return self.resolve
      }
      if command.contains("query-activities") {
        return self.launchers
      }
      if command.starts(with: ["pm", "path"]) {
        return self.packagePath
      }
      if command.starts(with: ["am", "force-stop"]) {
        return self.forceStop
      }
      if command.first == "date" {
        return self.date
      }
      if command.starts(with: ["am", "start"]) {
        return self.start
      }
      if command.first?.hasPrefix("for i in") == true {
        return try self.pid.get()
      }
      if command.starts(with: ["pm", "list", "packages", "-U"]) {
        return self.uid
      }
      if command.starts(with: ["logcat", "-d"]) {
        return self.uidLog
      }
      return AndroidEmulatorClientImplLogcatTests.result(1)
    }
  }

  /// 잠금이 있고 adb 에 켜짐으로 보이는 `Pixel` (emulator-5554). 앱 명령은 `replies`, 받기는 `stream`.
  static func booted(
    _ replies: Replies = Replies(),
    stream: FakeLogcatStream.Handler? = nil
  ) throws -> (Harness, FakeLogcatStream) {
    let adb = FakeADB()
    let fake = FakeLogcatStream(adb: adb, handler: stream)
    let harness = try Harness(adb: adb) { invocation, emit throws(CommandError) in
      try await fake.handle(invocation, emit)
    }
    try harness.locks.hold(harness.addDevice("Pixel"))
    adb.set(Self.serial, FakeADB.Emulator(name: "Pixel"))
    adb.onApp { arguments throws(CommandError) in try replies.respond(arguments) }
    return (harness, fake)
  }

  static func appCalls(_ harness: Harness) -> [[String]] {
    AndroidEmulatorClientImplAppTests.appCalls(harness)
  }

  static func launch(
    _ harness: Harness,
    _ events: FakeLogcatEvents
  ) async throws(AndroidEmulatorError) -> AndroidLogcatEnd {
    try await harness.client.launchWithLogcat(self.package, on: self.pixel) { events.append($0) }
  }

  // MARK: - 받기

  @Test("성공: 명령 순서, .launched 가 첫 줄보다 먼저 한 번, 조각 경계가 줄 가운데여도 줄로, 머리 줄은 빠지고, 143 이면 appExited")
  func streams() async throws {
    let (harness, _) = try Self.booted(stream: { _, emit throws(CommandError) in
      await emit(.stdout(Data("--------- beginning of main\n11-09 10:00:00.000  6502  6502 I Zy".utf8)))
      await emit(.stderr(Data("ignored\n".utf8)))
      await emit(.stdout(Data("gote: Process 6502 created\n--------- beginning of crash\n\tat a.b(C.java:1)\nlast"
          .utf8)))
      return Self.result(143)
    })
    defer { harness.cleanUp() }
    let events = FakeLogcatEvents()

    #expect(try await Self.launch(harness, events) == .appExited)

    #expect(events.all == [
      .launched,
      .lines(["11-09 10:00:00.000  6502  6502 I Zygote: Process 6502 created", "\tat a.b(C.java:1)"]),
      .lines(["last"]),
    ])
    #expect(Self.appCalls(harness) == [
      Self.resolveCall, Self.forceStopCall, Self.dateCall, Self.startCall, Self.pidCall, Self.streamCall,
    ])
    let stream = try #require(harness.command.invocations.last)
    #expect(stream.isStream)
    #expect(stream.environment == ["HOME": FileFacts.path(harness.home), "ADB_MDNS": "0"])
    let pidWait = try #require(harness.command.invocations.first { $0.arguments == Self.pidCall })
    #expect(pidWait.timeout == .seconds(30))
  }

  @Test("받기 끝: 143 밖의 종료 코드·adb 시작 실패는 connectionLost")
  func streamEnds() async throws {
    for code: Int32 in [255, 1, 130, 0] {
      let (harness, _) = try Self.booted(stream: { _, _ throws(CommandError) in Self.result(code) })
      defer { harness.cleanUp() }
      #expect(try await Self.launch(harness, FakeLogcatEvents()) == .connectionLost, "\(code)")
    }
    let (harness, _) = try Self.booted(stream: { _, _ throws(CommandError) in throw .launchFailed })
    defer { harness.cleanUp() }
    let events = FakeLogcatEvents()
    #expect(try await Self.launch(harness, events) == .connectionLost)
    #expect(events.all == [.launched])
  }

  @Test("받는 중 Task 취소는 던지지 않고 stopped")
  func cancelWhileStreaming() async throws {
    let (harness, _) = try Self.booted(stream: { _, emit throws(CommandError) in
      await emit(.stdout(Data("11-09 first\n".utf8)))
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3600))
      }
      throw .cancelled
    })
    defer { harness.cleanUp() }
    let events = FakeLogcatEvents()

    let running = Task { try await Self.launch(harness, events) }
    #expect(try await waitUntil { events.all.count == 2 })
    running.cancel()
    #expect(try await running.value == .stopped)
    #expect(events.all == [.launched, .lines(["11-09 first"])])
  }

  @Test("pid 전 취소: .launched 없이 stopped, 받기 명령 없음")
  func cancelBeforePID() async throws {
    var replies = Replies()
    replies.pid = .failure(.cancelled)
    let (harness, _) = try Self.booted(replies)
    defer { harness.cleanUp() }
    let events = FakeLogcatEvents()

    #expect(try await Self.launch(harness, events) == .stopped)
    #expect(events.all.isEmpty)
    #expect(!harness.command.invocations.contains { $0.isStream })
  }

  // MARK: - pid 전에 끝남

  @Test("pid 못 찾음: uid(정확한 줄) → 한 번 읽기 → .launched·줄(머리 줄 뺌)·appExited, 받기 명령 없음")
  func exitedBeforePID() async throws {
    var replies = Replies()
    replies.pid = .success(Self.result(1))
    replies.uidLog = Self.result(
      0,
      stdout: "--------- beginning of main\n11-09 10:00:00.000  6621  6621 I Zygote: Process 6621 created\n11-09 b\n"
    )
    let (harness, _) = try Self.booted(replies)
    defer { harness.cleanUp() }
    let events = FakeLogcatEvents()

    #expect(try await Self.launch(harness, events) == .appExited)
    #expect(events.all == [
      .launched, .lines(["11-09 10:00:00.000  6621  6621 I Zygote: Process 6621 created", "11-09 b"]),
    ])
    #expect(Self.appCalls(harness) == [
      Self.resolveCall, Self.forceStopCall, Self.dateCall, Self.startCall, Self.pidCall, Self.uidCall, Self.uidLogCall,
    ])
    #expect(!harness.command.invocations.contains { $0.isStream })
  }

  @Test("pid 못 찾음 + uid 없음, 또는 한 번 읽기 실패: .launched 뒤 줄 없이 connectionLost")
  func exitedBeforePIDUnreadable() async throws {
    var noUID = Replies()
    noUID.pid = .success(Self.result(1))
    noUID.uid = Self.result(0)
    var unreadable = Replies()
    unreadable.pid = .success(Self.result(1))
    unreadable.uidLog = Self.result(1, stderr: "logcat: -T 'x' not in time format.\n")
    for replies in [noUID, unreadable] {
      let (harness, _) = try Self.booted(replies)
      defer { harness.cleanUp() }
      let events = FakeLogcatEvents()
      #expect(try await Self.launch(harness, events) == .connectionLost)
      #expect(events.all == [.launched])
    }
  }

  // MARK: - .launched 전 실패
}

/// logcat 받기(`streamCancellable`) 흉내. 그 밖의 cancellable 명령(목록 읽기·앱 명령)은 adb 흉내의 답이다.
final class FakeLogcatStream: Sendable {
  typealias Handler = @Sendable (
    [String],
    _ emit: @Sendable (CommandOutput) async -> Void
  ) async throws(CommandError) -> CommandResult

  private let adb: FakeADB
  private let handler: Handler?

  init(adb: FakeADB, handler: Handler?) {
    self.adb = adb
    self.handler = handler
  }

  func handle(
    _ invocation: CommandClientFake.Invocation,
    _ emit: @Sendable (CommandOutput) async -> Void
  ) async throws(CommandError) -> CommandResult {
    if invocation.isStream, let handler = self.handler {
      return try await handler(invocation.arguments, emit)
    }
    return try self.adb.respond(invocation.arguments)
  }
}
