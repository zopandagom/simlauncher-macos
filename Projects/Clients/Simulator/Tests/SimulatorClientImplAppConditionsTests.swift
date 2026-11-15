import CommandInterface
import CommandTesting
import Core
import Foundation
import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// 앱 단위 테스트 조건(privacy·push)의 인자·환경·stdin·판정. 출력은 `PushOutput` 실측 원문과, 그 자리에 `// 합성`·`// 실측 줄임` 을
/// 적은 테스트 안 출력이다.
struct SimulatorClientImplAppConditionsTests {
  private static let device = VirtualDevice.ID("00000000-0000-0000-0000-000000000001")
  private static let udid = device.rawValue
  private static let app = AppBundleID("com.zopandagom.simlauncher.sampleapp")!
  private static let developer = URL(filePath: "/X/Xcode.app/Contents/Developer", directoryHint: .isDirectory)

  private static func client(_ command: CommandClientFake, provider: ProviderCounter? = nil) -> SimulatorClientImpl {
    SimulatorClientImpl(
      developerDirectory: provider.map { counter in { @Sendable in counter.provide() } },
      command: command,
      fileExists: { _ in false },
      baseEnvironment: [:]
    )
  }

  private static func payload(_ json: String) throws -> PushPayload {
    try PushPayload.json(json).get()
  }

  // MARK: - privacy

  @Test("privacy: provider 한 번, 같은 DEVELOPER_DIR 로 privacy <기기> <동작> <서비스> <번들> 한 번, stdin 없음")
  func privacy() async throws {
    let command = CommandClientFake { _ in .success() }
    let counter = ProviderCounter(returning: Self.developer)

    try await Self.client(command, provider: counter)
      .setPrivacy(.revoke, .mediaLibrary, for: Self.app, on: VirtualDevice.ID(Self.udid.lowercased()))

    #expect(command.invocations.map(\.arguments) == [
      ["simctl", "privacy", Self.udid, "revoke", "media-library", "com.zopandagom.simlauncher.sampleapp"],
    ])
    let invocation = try #require(command.invocations.first)
    #expect(invocation.executable == SimctlCommand.xcrun)
    #expect(invocation.environment["DEVELOPER_DIR"] == "/X/Xcode.app/Contents/Developer/")
    #expect(invocation.standardInput == nil)
    #expect(counter.calls == 1)
  }

  @Test(
    "privacy 실패: 405 → deviceNotBooted, Invalid device → deviceNotFound, exit 1·117 → commandFailed, xcrun 오류",
    arguments: [
      (CommandResult.failure(149, PushOutput.notBooted), SimulatorError.deviceNotBooted),
      (.failure(148, PushOutput.invalidDevice), .deviceNotFound),
      (
        // 실측 줄임: `grant notifications` stderr(exit 1)의 앞 세 줄만.
        .failure(
          1,
          PushOutput.prefix + "(domain=NSPOSIXErrorDomain, code=1):\n"
            + "Simulator device failed to complete the requested operation.\nOperation not permitted\n"
        ),
        .commandFailed
      ),
      // 실측 줄임: 번들 생략(exit 117)의 첫 줄만 (사용법 줄은 뺐다).
      (.failure(117, "Bundle identifier is required for grant actions\n"), .commandFailed),
      // 합성: xcrun 오류 문구.
      (.failure(1, "xcrun: error: missing DEVELOPER_DIR path: /nonexistent\n"), .developerToolsUnavailable),
    ]
  )
  func privacyFailures(_ result: CommandResult, _ expected: SimulatorError) async {
    let command = CommandClientFake { _ in result }
    await #expect(throws: expected) {
      try await Self.client(command).setPrivacy(.grant, .camera, for: Self.app, on: Self.device)
    }
  }

  @Test("privacy: 미설치 번들도 출력 없이 exit 0 이라 성공으로 본다 (판정하지 않는다)")
  func privacyNotInstalled() async throws {
    let command = CommandClientFake { _ in .success() }
    let missing = try #require(AppBundleID("com.example.notinstalled"))
    try await Self.client(command).setPrivacy(.grant, .location, for: missing, on: Self.device)
    #expect(command.invocations.count == 1)
  }

  // MARK: - push

  @Test("push: push <기기> <번들> - 에 payload 바이트를 그대로(공백·이스케이프 포함) stdin 으로 넘기고 sent")
  func push() async throws {
    let text = "{ \"aps\" : { \"alert\" : \"\\uac00 한글\" } }\n\n   "
    let command = CommandClientFake { _ in .success(Data(PushOutput.sent.utf8)) }
    let counter = ProviderCounter(returning: Self.developer)

    let outcome = try await Self.client(command, provider: counter)
      .sendPush(Self.payload(text), to: Self.app, on: Self.device)

    #expect(outcome == .sent)
    let invocation = try #require(command.invocations.first)
    #expect(command.invocations.count == 1)
    #expect(invocation.arguments == ["simctl", "push", Self.udid, "com.zopandagom.simlauncher.sampleapp", "-"])
    #expect(invocation.standardInput == Data(text.utf8))
    #expect(invocation.executable == SimctlCommand.xcrun)
    #expect(invocation.environment["DEVELOPER_DIR"] == "/X/Xcode.app/Contents/Developer/")
    #expect(counter.calls == 1)
  }

  @Test(
    "push 결과 매핑: 실측 출력(`PushOutput`)·합성 출력 → 결과·에러",
    arguments: [
      (
        CommandResult.failure(211, PushOutput.notAuthorized),
        Result<IOSPushOutcome, SimulatorError>.success(.notAuthorized)
      ),
      (.failure(210, PushOutput.noContent), .success(.noVisibleContent)),
      (.failure(121, PushOutput.noVisibleContent), .success(.noVisibleContent)),
      (.failure(28, PushOutput.tooLarge), .success(.payloadRejected)),
      (.failure(0, PushOutput.notJSON), .failure(.commandFailed)),
      (.failure(149, PushOutput.notBooted), .failure(.deviceNotBooted)),
      (.failure(148, PushOutput.invalidDevice), .failure(.deviceNotFound)),
      // 합성: xcrun 오류 문구, exit 0 인데 출력 없음.
      (.failure(1, "xcrun: error: missing DEVELOPER_DIR path: /nonexistent\n"), .failure(.developerToolsUnavailable)),
      (.success(), .failure(.commandFailed)),
    ]
  )
  func pushOutcomes(_ result: CommandResult, _ expected: Result<IOSPushOutcome, SimulatorError>) async throws {
    let command = CommandClientFake { _ in result }
    let payload = try Self.payload(#"{"aps":{"alert":"hi"}}"#)
    let actual: Result<IOSPushOutcome, SimulatorError>
    do throws(SimulatorError) {
      let outcome = try await Self.client(command).sendPush(payload, to: Self.app, on: Self.device)
      actual = .success(outcome)
    } catch {
      actual = .failure(error)
    }
    #expect(actual == expected)
  }

  // MARK: - 실행하지 않는 경우

  @Test("UDID 형식이 아니면 실행하지 않고 deviceNotFound, provider 가 nil 이면 developerToolsUnavailable (둘 다)")
  func noCommand() async throws {
    let command = CommandClientFake { _ in .success(Data(PushOutput.sent.utf8)) }
    let payload = try Self.payload(#"{"aps":{"alert":"hi"}}"#)
    let name = VirtualDevice.ID("iPhone 17")

    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.client(command).setPrivacy(.grant, .camera, for: Self.app, on: name)
    }
    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.client(command).sendPush(payload, to: Self.app, on: name)
    }
    let noXcode = ProviderCounter(returning: nil)
    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(command, provider: noXcode).setPrivacy(.grant, .camera, for: Self.app, on: Self.device)
    }
    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(command, provider: noXcode).sendPush(payload, to: Self.app, on: Self.device)
    }
    #expect(command.invocations.isEmpty)
  }

  @Test("실행 파일을 띄우지 못하면 developerToolsUnavailable")
  func launchFailed() async throws {
    let command = CommandClientFake { _ throws(CommandError) in throw .launchFailed }
    let payload = try Self.payload(#"{"aps":{"alert":"hi"}}"#)
    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(command).sendPush(payload, to: Self.app, on: Self.device)
    }
    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(command).setPrivacy(.reset, .photos, for: Self.app, on: Self.device)
    }
  }
}
