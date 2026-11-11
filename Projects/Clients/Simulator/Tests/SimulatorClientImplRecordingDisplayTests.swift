import CommandInterface
import CommandTesting
import Core
import Foundation
import SimulatorInterface
import Synchronization
import Testing
@testable import SimulatorImpl

/// recordVideo 가 화면이 둘인 기기(iPhone Duo)에서 화면을 고르지 않아 시작 전에 실패했을 때 기본 화면으로 다시 띄우는지.
extension SimulatorClientImplRecordingTests {
  @Test("화면을 고르지 않아 시작 전에 끝나면(iPhone Duo) 기본 화면을 골라 한 번 더 띄우고, 그 녹화로 판정한다")
  func retriesWithPrimaryDisplay() async throws {
    let command = try Self.command { invocation, emit throws(CommandError) in
      guard invocation.arguments.contains(SimctlCommand.displayOption) else {
        return .failure(22, SimctlCommandTests.chooseDisplay)
      }
      await emit(.stderr(Data("Recording started\n".utf8)))
      throw .cancelled
    }
    let calls = Mutex(0)

    let result = try await Self.client(command, fileSize: 10).recordVideo(on: Self.booted, to: Self.file) {
      calls.withLock { $0 += 1 }
    }

    let path = Self.file.path(percentEncoded: false)
    #expect(result == .saved)
    #expect(calls.withLock { $0 } == 1)
    #expect(command.invocations.map(\.arguments) == [
      Self.list,
      ["simctl", "io", Self.booted.rawValue, "recordVideo", "--codec=h264", "--mask=ignored", "--force", path],
      [
        "simctl", "io", Self.booted.rawValue, "recordVideo", "--codec=h264", "--mask=ignored", "--display=primary",
        "--force", path,
      ],
    ])
  }

  @Test("시작 신호 뒤에 끝났거나 화면 고르기 줄이 없으면 다시 띄우지 않는다")
  func noRetryAfterStartOrOtherFailure() async throws {
    let afterStart = try Self.command { _, emit throws(CommandError) in
      await emit(.stderr(Data("Recording started\n".utf8)))
      return .failure(22, SimctlCommandTests.chooseDisplay)
    }
    _ = try? await Self.client(afterStart, fileSize: 10).recordVideo(on: Self.booted, to: Self.file) {}
    #expect(afterStart.invocations.count == 2)

    let other = try Self.command(recording: Self.exited(.failure(22, "Invalid argument\n")))
    _ = try? await Self.client(other).recordVideo(on: Self.booted, to: Self.file) {}
    #expect(other.invocations.count == 2)
  }
}
