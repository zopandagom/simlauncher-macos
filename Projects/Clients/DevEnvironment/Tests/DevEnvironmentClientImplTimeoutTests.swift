import CommandInterface
import CommandTesting
import Core
import DevEnvironmentInterface
import Foundation
import Testing
@testable import DevEnvironmentImpl

/// 확인 명령의 시간 제한과, 호출한 Task 의 취소가 Xcode 선택에 미치지 않는지.
struct DevEnvironmentClientImplTimeoutTests {
  private static func client(
    _ command: CommandClientFake,
    _ tmp: TemporaryDirectory
  ) -> DevEnvironmentClientImpl {
    DevEnvironmentClientImpl(
      command: command,
      applicationsDirectory: tmp.applications,
      baseEnvironment: ["PATH": "/usr/bin"]
    )
  }

  @Test("확인 명령 셋은 runCancellable 로 30초 시간 제한, open 은 기존 run")
  func checkCommandsUseTimeout() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try tmp.makeXcode()
    let command = Responder.command(select: Responder.commandLineTools, firstLaunch: .exit(69), license: .exit(0))
    let client = Self.client(command, tmp)

    _ = try await client.checkEnvironment()
    try await client.openXcodeInAppStore()

    #expect(DevEnvironmentClientImpl.checkTimeout == .seconds(30))
    #expect(command.executables == ["xcode-select", "xcodebuild", "xcodebuild", "open"])
    for invocation in command.invocations.dropLast() {
      #expect(invocation.isCancellable)
      #expect(invocation.timeout == .seconds(30))
    }
    #expect(command.invocations.last?.isCancellable == false)
  }

  @Test("xcodebuild 확인이 시간 초과로 멈추면 checkFailed (두 단계 각각)", arguments: [false, true])
  func checkTimedOut(atLicense: Bool) async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try tmp.makeXcode()
    let command = Responder.command(
      select: Responder.commandLineTools,
      firstLaunch: atLicense ? .exit(69) : .stopped(.timedOut),
      license: .stopped(.timedOut)
    )

    await #expect(throws: DevEnvironmentError.checkFailed) {
      try await Self.client(command, tmp).checkEnvironment()
    }
  }

  @Test("xcode-select 가 시간 초과로 멈추면 선택 없음으로 보고 앱 폴더의 Xcode 를 고른다")
  func selectTimedOut() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let bundle = try tmp.makeXcode()
    let command = Responder.command(select: .stopped(.timedOut))

    #expect(try await Self.client(command, tmp).selectedXcode() == tmp.installation(bundle, 27, 1))
  }

  @Test("취소된 Task 에서도 selectedXcode 는 xcode-select 가 가리키는 Xcode (앱 폴더에 더 높은 버전이 있어도)")
  func cancelledSelectionKeepsXcodeSelect() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let selected = try tmp.makeXcode("Xcode-26.app", in: tmp.elsewhere, version: "26.0")
    try tmp.makeXcode("Xcode-beta.app", version: "27.2")
    let command = Responder.command(select: Responder.selecting(selected.appending(path: "Contents/Developer")))
    let client = Self.client(command, tmp)

    let chosen = await Self.inCancelledTask { await client.selectedXcode() }

    #expect(try chosen == tmp.installation(selected, 26))
  }

  @Test("취소된 Task 의 checkEnvironment: xcode-select 는 돌고, xcodebuild 는 그 Xcode 안의 것이며, 결과는 checkFailed")
  func cancelledCheck() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let selected = try tmp.makeXcode("Xcode-26.app", in: tmp.elsewhere, version: "26.0")
    try tmp.makeXcode("Xcode-beta.app", version: "27.2")
    let command = Responder.command(select: Responder.selecting(selected.appending(path: "Contents/Developer")))
    let client = Self.client(command, tmp)
    let expected = try tmp.installation(selected, 26)

    let result = await Self.inCancelledTask { () async -> Result<DevEnvironmentStatus, DevEnvironmentError> in
      do throws(DevEnvironmentError) {
        return try await .success(client.checkEnvironment())
      } catch {
        return .failure(error)
      }
    }

    #expect(command.executables == ["xcode-select", "xcodebuild"])
    #expect(command.invocations.last?.executable == XcodeCommand.xcodebuild(in: expected))
    #expect(result == .failure(.checkFailed))
  }

  /// 시작 전에 취소된 Task 안에서 `body` 를 실행한다.
  private static func inCancelledTask<T: Sendable>(_ body: @escaping @Sendable () async -> T) async -> T {
    let task = Task {
      while !Task.isCancelled {
        await Task.yield()
      }
      return await body()
    }
    task.cancel()
    return await task.value
  }
}
