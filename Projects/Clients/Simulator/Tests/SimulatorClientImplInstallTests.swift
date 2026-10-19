import Core
import Foundation
import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// install·launch 의 인자·환경·분류. 목록을 다시 읽지 않는다.
struct SimulatorClientImplInstallTests {
  private static let udid = "B66201ED-154C-4F97-A6C7-C88F42E8D3A7"
  private static let developer = URL(filePath: "/X/Xcode.app/Contents/Developer", directoryHint: .isDirectory)
  private static let app = URL(filePath: "/tmp/공백 경로/한글 앱.app", directoryHint: .isDirectory)
  private static let bundleID = AppBundleID("com.example.ok")!
  private static let shutdownStderr =
    "An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=405):\n"
      + "Unable to lookup in current state: Shutdown\n"

  // MARK: - install

  @Test("UDID 형식이 아니면 provider·프로세스 없이 deviceNotFound", arguments: ["", "-h", "iPhone 17", "booted"])
  func installInvalidUDID(raw: String) async throws {
    let runner = StubCommandRunner { _ in .success() }
    let counter = ProviderCounter(returning: Self.developer)

    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.client(runner, provider: counter).install(Self.app, on: VirtualDevice.ID(raw))
    }
    #expect(runner.invocations.isEmpty)
    #expect(counter.calls == 0)
  }

  @Test("파일 URL 이 아니면 실행하지 않고 appNotFound")
  func installNotFileURL() async throws {
    let runner = StubCommandRunner { _ in .success() }

    await #expect(throws: SimulatorError.appNotFound) {
      try await Self.client(runner).install(
        #require(URL(string: "https://example.com/A.app")),
        on: VirtualDevice.ID(Self.udid)
      )
    }
    #expect(runner.invocations.isEmpty)
  }

  @Test("대문자 UDID 와 표준화한 절대 경로(한글·공백 그대로)를 넘기고, 성공하면 목록을 읽지 않는다")
  func installArguments() async throws {
    let runner = StubCommandRunner { _ in .success() }
    let counter = ProviderCounter(returning: Self.developer)

    try await Self.client(runner, provider: counter).install(
      URL(filePath: "/tmp/공백 경로/x/../한글 앱.app", directoryHint: .isDirectory),
      on: VirtualDevice.ID(Self.udid.lowercased())
    )

    #expect(runner.invocations.count == 1)
    let invocation = try #require(runner.invocations.first)
    #expect(invocation.executable == SimctlCommand.xcrun)
    #expect(invocation.arguments == ["simctl", "install", Self.udid, "/tmp/공백 경로/한글 앱.app/"])
    #expect(invocation.environment["DEVELOPER_DIR"] == "/X/Xcode.app/Contents/Developer/")
    #expect(counter.calls == 1)
  }

  @Test("install 실패는 domain 줄로 분류한다")
  func installFailure() async throws {
    let runner = StubCommandRunner { _ in .failure(149, Self.shutdownStderr) }

    await #expect(throws: SimulatorError.deviceNotBooted) {
      try await Self.client(runner).install(Self.app, on: VirtualDevice.ID(Self.udid))
    }
    #expect(runner.invocations.count == 1)
  }

  @Test("잘못된 UTF-8 이 섞인 stderr 도 domain 줄로 분류한다")
  func installFailureWithInvalidUTF8() async throws {
    let stderr = Data(
      "An error was encountered processing the command (domain=IXUserPresentableErrorDomain, code=4):\n".utf8
    ) + Data([0xFF, 0xFE, 0x0A])
    let runner = StubCommandRunner { _ in CommandResult(exitCode: 4, stdout: Data(), stderr: stderr) }

    await #expect(throws: SimulatorError.appIncompatible) {
      try await Self.client(runner).install(Self.app, on: VirtualDevice.ID(Self.udid))
    }
  }

  @Test("프로세스를 시작하지 못하면 developerToolsUnavailable")
  func installLaunchFailure() async throws {
    let runner = StubCommandRunner { _ in throw StubCommandRunner.LaunchError() }

    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(runner).install(Self.app, on: VirtualDevice.ID(Self.udid))
    }
  }

  // MARK: - launch

  @Test("launch 도 UDID 형식이 아니면 실행하지 않고 deviceNotFound")
  func launchInvalidUDID() async throws {
    let runner = StubCommandRunner { _ in .success() }

    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.client(runner).launch(Self.bundleID, on: VirtualDevice.ID("--terminate-running-process"))
    }
    #expect(runner.invocations.isEmpty)
  }

  @Test("launch 는 기기 뒤에 번들 ID 를 넘기고, stdout 의 pid 는 읽지 않고 성공한다")
  func launchArguments() async throws {
    let runner = StubCommandRunner { _ in .success(Data("com.example.ok: 53947\n".utf8)) }
    let counter = ProviderCounter(returning: Self.developer)

    try await Self.client(runner, provider: counter).launch(Self.bundleID, on: VirtualDevice.ID(Self.udid))

    #expect(runner.invocations.map(\.arguments) == [["simctl", "launch", Self.udid, "com.example.ok"]])
    #expect(runner.invocations.first?.environment["DEVELOPER_DIR"] == "/X/Xcode.app/Contents/Developer/")
    #expect(counter.calls == 1)
  }

  @Test("launch 실패는 domain 줄로 분류한다")
  func launchFailure() async throws {
    let runner = StubCommandRunner { _ in
      .failure(
        4,
        "An error was encountered processing the command (domain=FBSOpenApplicationServiceErrorDomain, code=4):\n"
          + "The request to open \"com.example.ok\" failed.\n"
      )
    }

    await #expect(throws: SimulatorError.appNotInstalled) {
      try await Self.client(runner).launch(Self.bundleID, on: VirtualDevice.ID(Self.udid))
    }
    #expect(runner.invocations.count == 1)
  }

  private static func client(_ runner: StubCommandRunner, provider: ProviderCounter? = nil) -> SimulatorClientImpl {
    SimulatorClientImpl(
      developerDirectory: provider.map { counter in { @Sendable in counter.provide() } },
      runner: runner,
      fileExists: { _ in false },
      baseEnvironment: [:]
    )
  }
}
