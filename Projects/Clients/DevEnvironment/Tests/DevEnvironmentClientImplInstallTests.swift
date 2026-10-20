import CommandInterface
import CommandTesting
import Core
import DevEnvironmentInterface
import Foundation
import Synchronization
import Testing
@testable import DevEnvironmentImpl

/// `installDefaultIOSRuntime`: 고른 Xcode 의 xcodebuild 실행, 진행 알림 순서, 결과·에러 대응.
struct DevEnvironmentClientImplInstallTests {
  /// xcode-select 는 `select` 결과, xcodebuild `-downloadPlatform` 은 `install` 처리기로 답하는 Fake.
  private static func command(
    select: Responder.Outcome,
    install: @escaping CommandClientFake.CancellableHandler
  ) -> CommandClientFake {
    CommandClientFake(
      handler: { invocation throws(CommandError) in
        Issue.record("run 을 부르지 않아야 한다: \(invocation.executable.lastPathComponent)")
        throw .launchFailed
      },
      cancellableHandler: { invocation, emit throws(CommandError) in
        if invocation.executable.lastPathComponent == "xcode-select" {
          return try Responder.result(select)
        }
        return try await install(invocation, emit)
      }
    )
  }

  private static func client(_ command: CommandClientFake, _ tmp: TemporaryDirectory) -> DevEnvironmentClientImpl {
    DevEnvironmentClientImpl(
      command: command,
      applicationsDirectory: tmp.applications,
      baseEnvironment: ["PATH": "/usr/bin"]
    )
  }

  /// 실측 형식의 내려받기 출력.
  private static let downloadChunks: [String] = [
    "Finding content...\n",
    "Automatically resolved architecture variant for platform iOS as 'arm64'.\n",
    """
    \rDownloading iOS 27.1 Simulator (24A94232) (arm64): \
    \rDownloading iOS 27.1 Simulator (24A94232) (arm64): Preparing to download...
    """,
    "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 0.0% (73 kB of 3.76 GB) ",
    "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 50.0% (1.88 GB of 3.76 GB)",
    "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): Installing...             ",
    "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): Done.        ",
    "\niOS 27.1 (24A94232) - 0E1F2A3B-4C5D-6E7F-8091-A2B3C4D5E6F7\n",
  ]

  private static func emitting(_ chunks: [String], exitCode: Int32 = 0) -> CommandClientFake.CancellableHandler {
    { _, emit throws(CommandError) in
      var stdout = Data()
      for chunk in chunks {
        let data = Data(chunk.utf8)
        stdout.append(data)
        await emit(.stdout(data))
      }
      return CommandResult(exitCode: exitCode, stdout: stdout, stderr: Data())
    }
  }

  @Test("Xcode 가 없으면 xcodeNotFound, xcodebuild 는 실행하지 않고 진행도 알리지 않는다")
  func xcodeNotFound() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let command = Self.command(select: .exit(2), install: Self.emitting([]))
    let log = ProgressLog()

    await #expect(throws: RuntimeInstallError.xcodeNotFound) {
      try await Self.client(command, tmp).installDefaultIOSRuntime { log.append($0) }
    }
    #expect(command.executables == ["xcode-select"])
    #expect(log.all.isEmpty)
  }

  @Test("고른 Xcode 안의 xcodebuild 를 -downloadPlatform iOS·DEVELOPER_DIR·시간 제한 없이 실행한다")
  func runsDownloadPlatform() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let bundle = try tmp.makeXcode()
    let xcode = try tmp.installation(bundle, 27, 1)
    let command = Self.command(select: Responder.commandLineTools, install: Self.emitting(Self.downloadChunks))

    let outcome = try await Self.client(command, tmp).installDefaultIOSRuntime { _ in }

    #expect(outcome == .installed)
    let install = try #require(command.invocations.last)
    #expect(install.executable == XcodeCommand.xcodebuild(in: xcode))
    #expect(install.arguments == ["-downloadPlatform", "iOS"])
    #expect(install.environment == [
      "PATH": "/usr/bin",
      "DEVELOPER_DIR": xcode.developerDirectory.path(percentEncoded: false),
    ])
    #expect(install.isCancellable)
    #expect(install.timeout == nil)
  }

  @Test("진행은 .preparing 먼저, 그 뒤 해석 순서대로 알리고, 돌아오기 전에 모두 받는다")
  func progressOrder() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try tmp.makeXcode()
    let command = Self.command(select: Responder.commandLineTools, install: Self.emitting(Self.downloadChunks))
    let log = ProgressLog()

    _ = try await Self.client(command, tmp).installDefaultIOSRuntime { progress in
      // 느린 알림도 순서대로 끝까지 기다린다.
      try? await Task.sleep(for: .milliseconds(5))
      log.append(progress)
    }

    let phases: [RuntimeInstallProgress.Phase] = [.preparing, .downloading, .downloading, .installing]
    let fractions: [Double?] = [nil, 0, 0.5, nil]
    #expect(log.all.map(\.phase) == phases)
    #expect(log.all.map(\.fractionCompleted) == fractions)
    #expect(log.all[1].totalBytes == 3_760_000_000)
  }

  @Test("이미 설치됨 출력 + exit 0 → alreadyInstalled, 진행은 .preparing 하나")
  func alreadyInstalled() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try tmp.makeXcode()
    let chunks: [String] = [
      "Finding content...\n",
      "Automatically resolved architecture variant for platform iOS as 'arm64'.\n",
      "iOS 27.1 (24A94425) - 1A2B3C4D-5E6F-4071-8293-A4B5C6D7E8F9\n",
    ]
    let command = Self.command(select: Responder.commandLineTools, install: Self.emitting(chunks))
    let log = ProgressLog()

    let outcome = try await Self.client(command, tmp).installDefaultIOSRuntime { log.append($0) }

    #expect(outcome == .alreadyInstalled)
    #expect(log.all == [.preparing])
  }

  @Test("0 이 아닌 종료 코드는 failed", arguments: [Int32(1), 70])
  func nonZeroExit(exitCode: Int32) async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try tmp.makeXcode()
    let command = Self.command(
      select: Responder.commandLineTools,
      install: Self.emitting(Self.downloadChunks, exitCode: exitCode)
    )

    await #expect(throws: RuntimeInstallError.failed) {
      try await Self.client(command, tmp).installDefaultIOSRuntime { _ in }
    }
  }

  @Test(
    "CommandError 대응: launchFailed → launchFailed, cancelled → cancelled, timedOut → failed",
    arguments: [
      (CommandError.launchFailed, RuntimeInstallError.launchFailed),
      (.cancelled, .cancelled),
      (.timedOut, .failed),
    ] as [(CommandError, RuntimeInstallError)]
  )
  func commandErrors(thrown: CommandError, expected: RuntimeInstallError) async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try tmp.makeXcode()
    let command = Self.command(select: Responder.commandLineTools) { _, _ throws(CommandError) in
      throw thrown
    }

    await #expect(throws: expected) {
      try await Self.client(command, tmp).installDefaultIOSRuntime { _ in }
    }
  }

  @Test("내려받는 중 Task 를 취소하면 cancelled")
  func cancelDuringDownload() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try tmp.makeXcode()
    let started = Mutex(false)
    let command = Self.command(select: Responder.commandLineTools) { _, emit throws(CommandError) in
      await emit(.stdout(Data("\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 1.0% (1 GB of 100 GB)".utf8)))
      started.withLock { $0 = true }
      do {
        try await Task.sleep(for: .seconds(30))
      } catch {
        throw .cancelled
      }
      return .success()
    }
    let client = Self.client(command, tmp)
    let task = Task { try await client.installDefaultIOSRuntime { _ in } }
    await waitUntil { started.withLock { $0 } }

    task.cancel()

    await #expect(throws: RuntimeInstallError.cancelled) { try await task.value }
  }

  /// 스스로 끝난 xcodebuild 에 늦게 온 취소: 첫 조각만 넘긴 뒤 호출한 Task 를 취소하고, 남은 조각은 넘기지 못한 채
  /// 전체 출력을 결과로 돌려준다 (Command Impl 은 스스로 끝난 뒤 온 취소면 결과를 돌려준다).
  private static func lateCancel(fullOutput: [String]) -> CommandClientFake.CancellableHandler {
    { _, emit throws(CommandError) in
      await emit(.stdout(Data("Finding content...\n".utf8)))
      withUnsafeCurrentTask { $0?.cancel() }
      let stdout = Data(fullOutput.joined().utf8)
      return CommandResult(exitCode: 0, stdout: stdout, stderr: Data())
    }
  }

  @Test("늦게 온 취소로 넘기지 못한 조각에 내려받기 줄이 있으면 결과는 전체 출력으로 installed, 알림은 .preparing 하나")
  func lateCancelUsesFullOutput() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try tmp.makeXcode()
    let command = Self.command(
      select: Responder.commandLineTools,
      install: Self.lateCancel(fullOutput: Self.downloadChunks)
    )
    let client = Self.client(command, tmp)
    let log = ProgressLog()

    let outcome = try await Task { try await client.installDefaultIOSRuntime { log.append($0) } }.value

    #expect(outcome == .installed)
    #expect(log.all == [.preparing])
  }

  @Test("늦게 온 취소로 넘기지 못한 조각에 Download was cancelled. 가 있으면 exit 0 이어도 failed")
  func lateCancelSeesToolCancellation() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try tmp.makeXcode()
    let output: [String] = [
      "Finding content...\n",
      "\rDownloading iOS 27.1 Simulator (24A94232) (arm64): 14.9% (558.6 MB of 3.76 GB)",
      "\nDownload was cancelled.\n",
    ]
    let command = Self.command(select: Responder.commandLineTools, install: Self.lateCancel(fullOutput: output))
    let client = Self.client(command, tmp)

    await #expect(throws: RuntimeInstallError.failed) {
      try await Task { try await client.installDefaultIOSRuntime { _ in } }.value
    }
  }

  @Test("시작 전에 취소됐으면 xcode-select 는 끝까지 돌지만 xcodebuild 는 실행하지 않는다")
  func cancelledBeforeStart() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try tmp.makeXcode()
    let command = Self.command(select: Responder.commandLineTools, install: Self.emitting(Self.downloadChunks))
    let client = Self.client(command, tmp)
    let log = ProgressLog()

    let task = Task {
      while !Task.isCancelled {
        await Task.yield()
      }
      return try await client.installDefaultIOSRuntime { log.append($0) }
    }
    task.cancel()

    await #expect(throws: RuntimeInstallError.cancelled) { try await task.value }
    #expect(command.executables == ["xcode-select"])
    #expect(log.all.isEmpty)
  }
}

/// 받은 진행 알림 기록.
final class ProgressLog: Sendable {
  private let recorded = Mutex<[RuntimeInstallProgress]>([])

  var all: [RuntimeInstallProgress] {
    self.recorded.withLock { $0 }
  }

  func append(_ progress: RuntimeInstallProgress) {
    self.recorded.withLock { $0.append(progress) }
  }
}

/// 조건이 참이 될 때까지 차례를 넘긴다. 10초 안에 참이 되지 않으면 실패를 기록하고 돌아온다.
private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
  let deadline = ContinuousClock.now + .seconds(10)
  while !condition() {
    guard ContinuousClock.now < deadline else {
      Issue.record("10초 안에 조건이 참이 되지 않았다", sourceLocation: sourceLocation)
      return
    }
    await Task.yield()
  }
}
