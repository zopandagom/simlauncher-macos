import AndroidEmulatorInterface
import CommandInterface
import CommandTesting
import Core
import Foundation
import Synchronization
import Testing
@testable import AndroidEmulatorImpl

/// 기기 안 screenrecord·pull 흉내. 녹화 adb 는 pid 줄을 찍고 `kill -2` 나 호스트 취소까지 돈다. 그 밖의 명령은 `FakeADB` 로 넘긴다.
final class FakeScreenRecord: Sendable {
  enum Pull: Sendable {
    case normal
    /// 로컬에 일부를 쓴 뒤 실패한다. true 면 그 사이 기기가 adb 에서 사라진다.
    case fail(deviceGone: Bool)
    case timeout
  }

  struct Config: Sendable {
    var apiLevel = "37"
    var pidLine: String? = "4242\n"
    /// 시작 뒤 곧바로 이 종료 코드로 스스로 끝난다.
    var exitsByItself: Int32?
    /// 스스로 끝날 때의 stderr. nil 이면 종료 코드 ≠ 0 일 때 저장 공간 문구.
    var exitStderr: String?
    /// `kill -2` 뒤 녹화 adb 가 끝나는 종료 코드와 stderr.
    var killedExit: (code: Int32, stderr: String) = (0, "")
    var ignoresKill = false
    /// 끝난 뒤 기기 임시 파일 크기. nil 이면 없음.
    var remoteSize: Int? = 1000
    var pull = Pull.normal
  }

  private struct State {
    var config = Config()
    var killed = false
    var hostStopped = false
  }

  let adb: FakeADB
  private let state = Mutex(State())

  init(adb: FakeADB) {
    self.adb = adb
  }

  func configure(_ change: (inout Config) -> Void) {
    self.state.withLock { change(&$0.config) }
  }

  var hostStopped: Bool {
    self.state.withLock { $0.hostStopped }
  }

  func handle(
    _ invocation: CommandClientFake.Invocation,
    _ emit: @Sendable (CommandOutput) async -> Void
  ) async throws(CommandError) -> CommandResult {
    let arguments = invocation.arguments
    let rest = Array(arguments.dropFirst(2))
    let config = self.state.withLock { $0.config }
    if rest.count == 2, rest[0] == "shell", rest[1].hasPrefix("echo $$; exec screenrecord") {
      return try await self.record(config, emit)
    }
    if rest == ["shell", "getprop", "ro.build.version.sdk"] {
      return Self.result(0, stdout: config.apiLevel + "\r\n")
    }
    if rest.starts(with: ["shell", "kill", "-2"]) {
      self.state.withLock { $0.killed = true }
      return Self.result(0)
    }
    if rest.starts(with: ["shell", "rm", "-f"]) {
      return Self.result(0)
    }
    if rest.first == "pull", rest.count == 3 {
      return try self.pull(config, serial: arguments[1], remote: rest[1], local: rest[2])
    }
    let result = try self.adb.respond(arguments)
    if !result.stdout.isEmpty {
      await emit(.stdout(result.stdout))
    }
    return result
  }

  private func record(
    _ config: Config,
    _ emit: @Sendable (CommandOutput) async -> Void
  ) async throws(CommandError) -> CommandResult {
    if let pidLine = config.pidLine {
      await emit(.stdout(Data(pidLine.utf8)))
    }
    if let code = config.exitsByItself {
      let stderr = config.exitStderr ?? (code == 0 ? "" : "Unable to open '/data/local/tmp/x.mp4': No space left\n")
      return Self.result(code, stderr: stderr)
    }
    while true {
      if !config.ignoresKill, self.state.withLock({ $0.killed }) {
        return Self.result(config.killedExit.code, stderr: config.killedExit.stderr)
      }
      if Task.isCancelled {
        self.state.withLock { $0.hostStopped = true }
        throw .cancelled
      }
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  /// 성공이면 로컬을 새 파일로 바꿔 넣는다 (실측: inode 가 바뀐다).
  private func pull(
    _ config: Config,
    serial: String,
    remote: String,
    local: String
  ) throws(CommandError) -> CommandResult {
    switch config.pull {
    case .timeout:
      throw .timedOut
    case let .fail(deviceGone):
      try? Data(repeating: 0x41, count: 10).write(to: URL(filePath: local))
      if deviceGone {
        self.adb.set(serial, nil)
      }
      return Self.result(1, stderr: "adb: error: cannot create '\(local)': No space left on device\n")
    case .normal:
      guard let size = config.remoteSize else {
        return Self.result(
          1,
          stderr: "adb: error: failed to stat remote object '\(remote)': No such file or directory\n"
        )
      }
      try? FileManager.default.removeItem(atPath: local)
      try? Data(repeating: 0x41, count: size).write(to: URL(filePath: local))
      return Self.result(0, stdout: "\(remote): 1 file pulled.\n")
    }
  }

  private static func result(_ code: Int32, stdout: String = "", stderr: String = "") -> CommandResult {
    CommandResult(exitCode: code, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8))
  }
}

/// 시작 신호 횟수.
final class StartCounter: Sendable {
  private let count = Mutex(0)

  var value: Int {
    self.count.withLock { $0 }
  }

  func increment() {
    self.count.withLock { $0 += 1 }
  }
}

/// 켜진 기기의 스크린샷·녹화: 사전 확인, 예약 파일 쓰기, 기기 안 멈춤·가져오기·정리 순서와 결과.
struct AndroidEmulatorClientImplCaptureTests {
  static let pixel = AndroidVirtualDevice.ID("Pixel")
  static let serial = "emulator-5554"
  static let png = Data([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
  ])

  /// 화면이 꺼진 폴더블에서 screenrecord 가 찍은 stderr (실측).
  static let displayOffStderr = "ERROR: UNASSIGNED_LAYER_STACK, please check your display state.\n"

  static var timing: AndroidEmulatorClientImpl.Timing {
    var timing = Harness.timing
    timing.recordingStopLimit = .milliseconds(200)
    timing.recordingSettle = .milliseconds(10)
    return timing
  }

  /// 잠금이 있고 adb 에 켜짐으로 보이는 `Pixel` 과 녹화 흉내.
  static func booted() throws -> (Harness, FakeScreenRecord) {
    let adb = FakeADB()
    let recorder = FakeScreenRecord(adb: adb)
    let harness = try Harness(timing: Self.timing, adb: adb) { invocation, emit throws(CommandError) in
      try await recorder.handle(invocation, emit)
    }
    try harness.locks.hold(harness.addDevice("Pixel"))
    adb.set(Self.serial, FakeADB.Emulator(name: "Pixel"))
    return (harness, recorder)
  }

  /// Workspace 가 예약한 것 같은 빈 파일.
  static func reserved(_ harness: Harness, _ name: String = "shot.png") throws -> URL {
    try FileTree.file(harness.directory.url, name, contents: "")
    return harness.directory.url.appending(path: name)
  }

  static func size(_ url: URL) -> Int? {
    (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.size] as? Int
  }

  /// 목록 읽기를 뺀 adb 호출.
  static func captureCalls(_ harness: Harness) -> [[String]] {
    AndroidEmulatorClientImplAppTests.appCalls(harness)
  }

  // MARK: - 스크린샷

  @Test("스크린샷: exec-out 'screencap -p 2>/dev/null' 출력(PNG)을 예약 파일에 쓴다 (30초 한도)")
  func screenshot() async throws {
    let harness = try AndroidEmulatorClientImplAppTests.booted()
    defer { harness.cleanUp() }
    harness.adb.onApp { _ in CommandResult(exitCode: 0, stdout: Self.png, stderr: Data()) }
    let file = try Self.reserved(harness)

    try await harness.client.screenshot(on: Self.pixel, to: file)

    #expect(try Data(contentsOf: file) == Self.png)
    let call = try #require(harness.command.invocations.last)
    #expect(call.arguments == ["-s", Self.serial, "exec-out", "screencap -p 2>/dev/null"])
    #expect(call.timeout == .seconds(30))
  }

  @Test("스크린샷: 꺼진 기기는 명령 없이 deviceNotBooted, 종료 코드 ≠ 0·PNG 아님은 captureFailed (파일 그대로)")
  func screenshotFailures() async throws {
    let harness = try AndroidEmulatorClientImplAppTests.booted()
    defer { harness.cleanUp() }
    try harness.addDevice("Off")
    let file = try Self.reserved(harness)

    #expect(await thrownError { try await harness.client.screenshot(on: .init("Off"), to: file) } == .deviceNotBooted)
    #expect(Self.captureCalls(harness).isEmpty)

    harness.adb.onApp { _ in CommandResult(exitCode: 0, stdout: Data("not png".utf8), stderr: Data()) }
    #expect(await thrownError { try await harness.client.screenshot(on: Self.pixel, to: file) } == .captureFailed)
    harness.adb.onApp { _ in CommandResult(exitCode: 1, stdout: Self.png, stderr: Data()) }
    #expect(await thrownError { try await harness.client.screenshot(on: Self.pixel, to: file) } == .captureFailed)
    harness.adb.onApp { _ throws(CommandError) in throw .timedOut }
    #expect(await thrownError { try await harness.client.screenshot(on: Self.pixel, to: file) } == .captureFailed)
    #expect(Self.size(file) == 0)
  }

  @Test("스크린샷: 예약 파일이 없거나 링크면 만들거나 따라가지 않고 captureFileUnwritable")
  func screenshotUnwritable() async throws {
    let harness = try AndroidEmulatorClientImplAppTests.booted()
    defer { harness.cleanUp() }
    harness.adb.onApp { _ in CommandResult(exitCode: 0, stdout: Self.png, stderr: Data()) }
    let missing = harness.directory.url.appending(path: "missing.png")
    #expect(await thrownError { try await harness.client.screenshot(on: Self.pixel, to: missing) } ==
      .captureFileUnwritable)
    #expect(!FileTree.exists(missing))

    try FileTree.file(harness.directory.url, "target.png", contents: "keep")
    try FileTree.link(harness.directory.url, "link.png", to: "target.png")
    let link = harness.directory.url.appending(path: "link.png")
    #expect(await thrownError { try await harness.client.screenshot(on: Self.pixel, to: link) } ==
      .captureFileUnwritable)
    #expect(FileTree.read(harness.directory.url, "target.png") == "keep")

    try FileTree.directory(harness.directory.url, "folder.png")
    let folder = harness.directory.url.appending(path: "folder.png")
    #expect(await thrownError { try await harness.client.screenshot(on: Self.pixel, to: folder) } ==
      .captureFileUnwritable)
  }

  @Test("파일 쓰기가 중간에 실패하면 0바이트로 자른다, EINTR 은 다시 쓴다")
  func partialWriteTruncates() throws {
    let directory = try TemporaryDirectory()
    defer { directory.remove() }
    try FileTree.file(directory.url, "shot.png", contents: "")
    let file = directory.url.appending(path: "shot.png")
    var calls = 0

    let error = Result { () throws(AndroidEmulatorError) in
      try CaptureFile.write(Self.png, to: file) { descriptor, buffer in
        calls += 1
        guard calls == 1 else {
          errno = EIO
          return -1
        }
        return write(descriptor, buffer.baseAddress, 4)
      }
    }
    guard case .failure(.captureFileUnwritable) = error else {
      Issue.record("captureFileUnwritable 이 아니다: \(error)")
      return
    }
    #expect(Self.size(file) == 0)

    var interrupted = false
    try CaptureFile.write(Self.png, to: file) { descriptor, buffer in
      if !interrupted {
        interrupted = true
        errno = EINTR
        return -1
      }
      return write(descriptor, buffer.baseAddress, buffer.count)
    }
    #expect(try Data(contentsOf: file) == Self.png)
  }
}

// MARK: - 녹화

extension AndroidEmulatorClientImplCaptureTests {
  @Test("녹화: 정리 → pid 줄에 onStarted 한 번 → 취소 → kill -2 <pid> → pull → 기기 파일 지우기, saved")
  func recordAndStop() async throws {
    let (harness, _) = try Self.booted()
    defer { harness.cleanUp() }
    let file = try Self.reserved(harness, "rec.mp4")
    let started = StartCounter()

    let task = Task {
      try await harness.client.recordScreen(on: Self.pixel, to: file) { started.increment() }
    }
    #expect(try await waitUntil { started.value == 1 })
    task.cancel()
    let result = try await task.value

    #expect(result == .saved)
    #expect(started.value == 1)
    #expect(Self.size(file) == 1000)
    let calls = Self.captureCalls(harness)
    #expect(calls.count == 6)
    guard calls.count == 6 else { return }
    let record = calls[2][3]
    let remote = String(record.dropFirst("echo $$; exec screenrecord --time-limit 0 ".count))
    #expect(record.hasPrefix("echo $$; exec screenrecord --time-limit 0 /data/local/tmp/simlauncher-recording-"))
    #expect(remote.hasSuffix(".mp4"))
    #expect(calls == [
      ["-s", Self.serial, "shell", "getprop", "ro.build.version.sdk"],
      ["-s", Self.serial, "shell", "rm", "-f", "/data/local/tmp/simlauncher-recording-*.mp4"],
      ["-s", Self.serial, "shell", record],
      ["-s", Self.serial, "shell", "kill", "-2", "4242"],
      ["-s", Self.serial, "pull", remote, FileFacts.path(file)],
      ["-s", Self.serial, "shell", "rm", "-f", remote],
    ])
    let recordCall = try #require(harness.command.invocations.first { $0.arguments == calls[2] })
    #expect(recordCall.timeout == nil)
    let pullCall = try #require(harness.command.invocations.first { $0.arguments == calls[4] })
    #expect(pullCall.timeout == .seconds(600))
  }

  @Test("녹화: 시작 전에 취소됐으면 명령 없이 stoppedBeforeStart")
  func cancelledBeforeStart() async throws {
    let (harness, _) = try Self.booted()
    defer { harness.cleanUp() }
    let file = try Self.reserved(harness, "rec.mp4")
    let started = StartCounter()

    let task = Task {
      while !Task.isCancelled {
        await Task.yield()
      }
      return try await harness.client.recordScreen(on: Self.pixel, to: file) { started.increment() }
    }
    task.cancel()

    #expect(try await task.value == .stoppedBeforeStart)
    #expect(started.value == 0)
    #expect(harness.command.invocations.isEmpty)
  }

  @Test("녹화: 시작 신호 전에 멈추면 kill 없이 호스트에서 멈춘다. 화면이 없으면 알림 없이 끝, 가져왔으면 saved (기기 파일은 지운다)")
  func stopBeforeSignal() async throws {
    let cases: [(Int?, AndroidScreenRecordingResult)] = [
      (nil, .stoppedBeforeStart),
      (0, .stoppedBeforeStart),
      (1000, .saved),
    ]
    for (remoteSize, expected) in cases {
      let (harness, recorder) = try Self.booted()
      defer { harness.cleanUp() }
      recorder.configure {
        $0.pidLine = nil
        $0.remoteSize = remoteSize
      }
      let file = try Self.reserved(harness, "rec.mp4")

      let task = Task { try await harness.client.recordScreen(on: Self.pixel, to: file) {} }
      #expect(try await waitUntil { Self.captureCalls(harness).count == 3 })
      task.cancel()

      #expect(try await task.value == expected, "\(String(describing: remoteSize))")
      #expect(recorder.hostStopped)
      #expect(Self.size(file) == (remoteSize ?? 0))
      let calls = Self.captureCalls(harness)
      #expect(!calls.contains { $0.contains("kill") })
      let last = try #require(calls.last)
      #expect(Array(last.prefix(5)) == ["-s", Self.serial, "shell", "rm", "-f"])
      #expect(last.last?.hasPrefix("/data/local/tmp/simlauncher-recording-") == true)
      #expect(last.last?.hasSuffix("*.mp4") == false)
    }
  }

  @Test("녹화: kill 뒤 한도 안에 끝나지 않으면 호스트에서 대신 멈추고, 끝난 뒤에야 돌아와 savedAfterFailure")
  func hostStopsWhenKillIgnored() async throws {
    let (harness, recorder) = try Self.booted()
    defer { harness.cleanUp() }
    recorder.configure { $0.ignoresKill = true }
    let file = try Self.reserved(harness, "rec.mp4")
    let started = StartCounter()

    let task = Task { try await harness.client.recordScreen(on: Self.pixel, to: file) { started.increment() } }
    #expect(try await waitUntil { started.value == 1 })
    task.cancel()

    #expect(try await task.value == .savedAfterFailure)
    #expect(recorder.hostStopped)
    #expect(started.value == 1)
    #expect(Self.captureCalls(harness).contains(["-s", Self.serial, "shell", "kill", "-2", "4242"]))
  }

  @Test("녹화: 스스로 끝나면 kill 을 보내지 않는다, API 33 은 제한 인자 없이 시작해 3분 제한, API 37 은 중간에 끝남")
  func exitsByItself() async throws {
    for (level, expected) in [("33", AndroidScreenRecordingResult.savedAtTimeLimit), ("37", .savedAfterFailure)] {
      let (harness, recorder) = try Self.booted()
      defer { harness.cleanUp() }
      recorder.configure {
        $0.apiLevel = level
        $0.exitsByItself = 0
      }
      let file = try Self.reserved(harness, "rec.mp4")

      #expect(try await harness.client.recordScreen(on: Self.pixel, to: file) {} == expected, "\(level)")
      let calls = Self.captureCalls(harness)
      #expect(!calls.contains { $0.contains("kill") }, "\(level)")
      #expect(calls.count > 2 && calls[2][3].contains("--time-limit 0") == (level == "37"), "\(level)")
    }
  }

  @Test("녹화: 화면 없이 실패로 끝나면 recordingFailed, 예약 파일은 0바이트 그대로")
  func startFailure() async throws {
    let (harness, recorder) = try Self.booted()
    defer { harness.cleanUp() }
    recorder.configure {
      $0.exitsByItself = 1
      $0.remoteSize = nil
    }
    let file = try Self.reserved(harness, "rec.mp4")

    let error = await thrownError { _ = try await harness.client.recordScreen(on: Self.pixel, to: file) {} }
    #expect(error == .recordingFailed)
    #expect(Self.size(file) == 0)
    #expect(Self.captureCalls(harness).filter { $0.contains("rm") }.count == 1)
  }

  @Test("녹화: 화면이 꺼져 실패로 끝나면(UNASSIGNED_LAYER_STACK) recordingDisplayOff, 0바이트 기기 파일은 지운다")
  func displayOff() async throws {
    let (harness, recorder) = try Self.booted()
    defer { harness.cleanUp() }
    recorder.configure {
      $0.pidLine = "2750\n"
      $0.exitsByItself = 218
      $0.exitStderr = Self.displayOffStderr
      $0.remoteSize = 0
    }
    let file = try Self.reserved(harness, "rec.mp4")
    let started = StartCounter()

    let error = await thrownError {
      _ = try await harness.client.recordScreen(on: Self.pixel, to: file) { started.increment() }
    }
    #expect(error == .recordingDisplayOff)
    #expect(started.value == 1)
    #expect(Self.size(file) == 0)
    let calls = Self.captureCalls(harness)
    #expect(calls.count == 5)
    guard calls.count == 5 else { return }
    let remote = String(calls[2][3].dropFirst("echo $$; exec screenrecord --time-limit 0 ".count))
    #expect(calls[3] == ["-s", Self.serial, "pull", remote, FileFacts.path(file)])
    #expect(calls[4] == ["-s", Self.serial, "shell", "rm", "-f", remote])
  }

  @Test("녹화: 멈춤 요청 뒤에는 화면 꺼짐 문구를 보지 않는다 (화면이 없으면 알림 없이 끝)")
  func displayOffAfterStop() async throws {
    let (harness, recorder) = try Self.booted()
    defer { harness.cleanUp() }
    recorder.configure {
      $0.killedExit = (218, Self.displayOffStderr)
      $0.remoteSize = 0
    }
    let file = try Self.reserved(harness, "rec.mp4")
    let started = StartCounter()

    let task = Task { try await harness.client.recordScreen(on: Self.pixel, to: file) { started.increment() } }
    #expect(try await waitUntil { started.value == 1 })
    task.cancel()

    #expect(try await task.value == .stoppedBeforeStart)
  }

  @Test("녹화: 가져오기 실패 → 기기가 사라졌으면 recordingLost, online 이면 captureFileUnwritable. 둘 다 기기 파일을 남기고 로컬은 0바이트")
  func pullFailures() async throws {
    for (gone, expected) in [(true, AndroidEmulatorError.recordingLost), (false, .captureFileUnwritable)] {
      let (harness, recorder) = try Self.booted()
      defer { harness.cleanUp() }
      recorder.configure { $0.pull = .fail(deviceGone: gone) }
      let file = try Self.reserved(harness, "rec.mp4")
      let started = StartCounter()

      let task = Task { try await harness.client.recordScreen(on: Self.pixel, to: file) { started.increment() } }
      #expect(try await waitUntil { started.value == 1 })
      task.cancel()

      #expect(await thrownError { _ = try await task.value } == expected, "\(gone)")
      #expect(Self.size(file) == 0, "\(gone)")
      let calls = Self.captureCalls(harness)
      #expect(calls.last?.dropFirst(2).first == "pull", "\(gone)")
      // 원인을 가르려고 adb devices 를 한 번 더 부르고, 기기 파일은 지우지 않는다.
      #expect(harness.adbCalls.last == ["devices"], "\(gone)")
    }
  }

  @Test("녹화: 가져오기가 한도를 넘으면 recordingTransferTimedOut, 기기 파일을 남긴다")
  func pullTimeout() async throws {
    let (harness, recorder) = try Self.booted()
    defer { harness.cleanUp() }
    recorder.configure { $0.pull = .timeout }
    let file = try Self.reserved(harness, "rec.mp4")
    let started = StartCounter()

    let task = Task { try await harness.client.recordScreen(on: Self.pixel, to: file) { started.increment() } }
    #expect(try await waitUntil { started.value == 1 })
    task.cancel()

    #expect(await thrownError { _ = try await task.value } == .recordingTransferTimedOut)
    #expect(Self.captureCalls(harness).last?.dropFirst(2).first == "pull")
  }

  @Test("녹화: 꺼진 기기는 녹화 명령 없이 deviceNotBooted")
  func recordRejectsNotBooted() async throws {
    let (harness, _) = try Self.booted()
    defer { harness.cleanUp() }
    try harness.addDevice("Off")
    let file = try Self.reserved(harness, "rec.mp4")

    #expect(await thrownError { _ = try await harness.client.recordScreen(on: .init("Off"), to: file) {} } ==
      .deviceNotBooted)
    #expect(Self.captureCalls(harness).isEmpty)
  }
}
