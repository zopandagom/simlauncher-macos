import CommandInterface
import Core
import Foundation
import SimulatorInterface

// MARK: - 테스트 조건 (앱 하나: 개인정보 접근, 푸시)

public extension SimulatorClientImpl {
  /// 성공은 출력 없이 exit 0 이고, 설치되지 않은 번들도 exit 0 이라(실측) 반영 여부는 보지 않는다.
  func setPrivacy(
    _ action: IOSPrivacyAction,
    _ service: IOSPrivacyService,
    for app: AppBundleID,
    on id: VirtualDevice.ID
  ) async throws(SimulatorError) {
    guard let udid = SimctlCommand.validatedUDID(id.rawValue) else {
      throw .deviceNotFound
    }
    let directory = try await self.resolveDeveloperDirectory()
    let result = try await self.run(
      SimctlCommand.xcrun,
      SimctlCommand.privacy(udid: udid, action: action, service: service, bundleID: app.rawValue),
      developerDirectory: directory,
      launchFailure: .developerToolsUnavailable
    )
    guard result.exitCode == 0 else {
      throw SimctlErrorClassifier.bootedDeviceCommandError(exitCode: result.exitCode, stderr: Self.stderr(result))
    }
  }

  /// payload 바이트를 그대로 stdin 으로 넘긴다 (simctl 은 받은 바이트를 그대로 세어 4096 을 넘으면 거절한다, 실측).
  func sendPush(
    _ payload: PushPayload,
    to app: AppBundleID,
    on id: VirtualDevice.ID
  ) async throws(SimulatorError) -> IOSPushOutcome {
    guard let udid = SimctlCommand.validatedUDID(id.rawValue) else {
      throw .deviceNotFound
    }
    let directory = try await self.resolveDeveloperDirectory()
    let result = try await self.run(
      SimctlCommand.xcrun,
      SimctlCommand.push(udid: udid, bundleID: app.rawValue),
      standardInput: payload.data,
      developerDirectory: directory,
      launchFailure: .developerToolsUnavailable
    )
    return try SimctlErrorClassifier.pushOutcome(
      exitCode: result.exitCode,
      stdout: Self.stderr(result.stdout),
      stderr: Self.stderr(result)
    ).get()
  }
}

// MARK: - 도우미 (모듈 안에서만)

extension SimulatorClientImpl {
  /// `run(_:_:developerDirectory:launchFailure:)` 과 같고, `standardInput` 바이트를 stdin 으로 넘긴다 (push 의 payload).
  func run(
    _ executable: URL,
    _ arguments: [String],
    standardInput: Data,
    developerDirectory: URL?,
    launchFailure: SimulatorError
  ) async throws(SimulatorError) -> CommandResult {
    let environment = SimctlCommand.environment(base: self.baseEnvironment, developerDirectory: developerDirectory)
    do {
      return try await self.command.run(executable, arguments, environment: environment, standardInput: standardInput)
    } catch {
      throw launchFailure
    }
  }
}
