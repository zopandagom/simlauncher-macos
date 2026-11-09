import AndroidEmulatorInterface
import CommandInterface
import CommandTesting
import Core
import Foundation
import Synchronization
import Testing
@testable import AndroidEmulatorImpl

/// 로그 받기와 함께 하는 앱 실행의 실패 경로: 화면 없음·고르기 화면·am start·사전 단계·꺼진 기기·pid 기다림 실패.
extension AndroidEmulatorClientImplLogcatTests {
  @Test("화면이 없으면 pm path 로 가린다 (rc 1 → notInstalled, rc 0 → noLauncherActivity), force-stop 없음")
  func noActivity() async throws {
    for (code, expected) in [(Int32(1), AndroidLaunchFailure.notInstalled), (0, .noLauncherActivity)] {
      var replies = Replies()
      replies.resolve = Self.result(0, stdout: "No activity found\n")
      replies.packagePath = Self.result(code)
      let (harness, _) = try Self.booted(replies)
      defer { harness.cleanUp() }
      let events = FakeLogcatEvents()

      #expect(await thrownError { _ = try await Self.launch(harness, events) } == .launchFailed(expected))
      #expect(Self.appCalls(harness) == [
        Self.resolveCall, ["-s", "emulator-5554", "shell", "pm", "path", "org.videolan.vlc"],
      ])
      #expect(events.all.isEmpty)
    }
  }

  @Test("launcher 둘 이상(고르기 화면): query-activities 의 첫 화면으로 실행한다 (실측 출력)")
  func ambiguous() async throws {
    var replies = Replies()
    replies.resolve = Self.chooser
    replies.launchers = Self.result(0, stdout: Self.twoLaunchers)
    let (harness, _) = try Self.booted(replies, stream: { _, _ throws(CommandError) in Self.result(143) })
    defer { harness.cleanUp() }

    #expect(try await Self.launch(harness, FakeLogcatEvents()) == .appExited)
    let calls = Self.appCalls(harness)
    #expect(calls[1] == [
      "-s", "emulator-5554", "shell", "cmd", "package", "query-activities", "--brief",
      "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", "org.videolan.vlc",
    ])
    #expect(calls[4] == [
      "-s",
      "emulator-5554",
      "shell",
      "am",
      "start",
      "-n",
      "'org.videolan.vlc/android.app.Activity'",
    ])
  }

  @Test("고르기 화면 뒤 query 가 비면 pm path 로 가리고, 켜는 중이면 앱 명령 없이 deviceNotBooted")
  func ambiguousFailures() async throws {
    for (code, expected) in [(Int32(1), AndroidLaunchFailure.notInstalled), (0, .noLauncherActivity)] {
      var replies = Replies()
      replies.resolve = Self.chooser
      replies.launchers = Self.result(0, stdout: "No activities found\n")
      replies.packagePath = Self.result(code)
      let (harness, _) = try Self.booted(replies)
      defer { harness.cleanUp() }
      #expect(await thrownError { _ = try await Self.launch(harness, FakeLogcatEvents()) } == .launchFailed(expected))
      #expect(!Self.appCalls(harness).contains(Self.forceStopCall))
    }
    var replies = Replies()
    replies.resolve = Self.chooser
    replies.launchers = Self.result(20, stderr: "cmd: Can't find service: package\n")
    let (harness, _) = try Self.booted(replies)
    defer { harness.cleanUp() }
    #expect(await thrownError { _ = try await Self.launch(harness, FakeLogcatEvents()) } == .deviceNotBooted)
    #expect(Self.appCalls(harness).count == 2)
  }

  @Test("am start 가 Error 줄이면 appCommandFailed, pid·받기 없음")
  func startFails() async throws {
    var replies = Replies()
    replies.start = Self.result(
      0,
      stdout: "Starting: Intent { }\nError type 3\nError: Activity class does not exist.\n"
    )
    let (harness, _) = try Self.booted(replies)
    defer { harness.cleanUp() }
    let events = FakeLogcatEvents()

    #expect(await thrownError { _ = try await Self.launch(harness, events) } == .appCommandFailed)
    #expect(Self.appCalls(harness) == [Self.resolveCall, Self.forceStopCall, Self.dateCall, Self.startCall])
    #expect(events.all.isEmpty)
  }

  @Test("force-stop·date 의 실패: 끊김은 deviceNotBooted, 그 밖 appCommandFailed")
  func earlyStepFailures() async throws {
    var stopFails = Replies()
    stopFails.forceStop = Self.result(1, stderr: "adb: device offline\n")
    var dateFails = Replies()
    dateFails.date = Self.result(0, stdout: "abc\n")
    for (replies, expected) in [(stopFails, AndroidEmulatorError.deviceNotBooted), (dateFails, .appCommandFailed)] {
      let (harness, _) = try Self.booted(replies)
      defer { harness.cleanUp() }
      #expect(await thrownError { _ = try await Self.launch(harness, FakeLogcatEvents()) } == expected)
      #expect(!Self.appCalls(harness).contains(Self.startCall))
    }
  }

  @Test("꺼진 기기: 앱 명령 없이 deviceNotBooted")
  func notBooted() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("Pixel")

    #expect(await thrownError { _ = try await Self.launch(harness, FakeLogcatEvents()) } == .deviceNotBooted)
    #expect(Self.appCalls(harness).isEmpty)
  }

  @Test(
    "pid 기다림: 끊김 문구는 deviceNotBooted, 시간 한도 초과는 adbUnavailable, 종료 1 인데 stdout 이 있으면 appCommandFailed (uid 로 가지 않음)"
  )
  func pidWaitFailures() async throws {
    let cases: [(Result<CommandResult, CommandError>, AndroidEmulatorError)] = [
      (.success(Self.result(1, stderr: "adb: device 'emulator-5554' not found\n")), .deviceNotBooted),
      (.failure(.timedOut), .adbUnavailable),
      (.success(Self.result(1, stdout: "/system/bin/sh: seq: inaccessible or not found\n")), .appCommandFailed),
    ]
    for (reply, expected) in cases {
      var replies = Replies()
      replies.pid = reply
      let (harness, _) = try Self.booted(replies)
      defer { harness.cleanUp() }
      let events = FakeLogcatEvents()

      #expect(await thrownError { _ = try await Self.launch(harness, events) } == expected)
      #expect(events.all.isEmpty)
      #expect(!Self.appCalls(harness).contains(Self.uidCall))
      #expect(!harness.command.invocations.contains { $0.isStream })
    }
  }
}
