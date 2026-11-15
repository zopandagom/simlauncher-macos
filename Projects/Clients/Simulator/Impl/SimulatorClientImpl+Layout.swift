import CommandInterface
import Core
import Foundation
import SimulatorInterface

// MARK: - 실행 중인 앱 목록·앱 지우기 (iOS 레이아웃 보기가 쓰고, 앱 지우기는 설치된 앱 시트도 쓴다)

public extension SimulatorClientImpl {
  /// 사전 목록 확인·재조회는 하지 않는다 (꺼진 기기·없는 기기는 simctl 의 실패를 분류한다).
  func runningApplications(on id: VirtualDevice.ID) async throws(SimulatorError) -> [AppBundleID] {
    guard let udid = SimctlCommand.validatedUDID(id.rawValue) else {
      throw .deviceNotFound
    }
    let directory = try await self.resolveDeveloperDirectory()
    let result = try await self.run(
      SimctlCommand.xcrun,
      SimctlCommand.spawnLaunchctlList(udid: udid),
      developerDirectory: directory,
      launchFailure: .developerToolsUnavailable
    )
    guard result.exitCode == 0 else {
      throw SimctlErrorClassifier.bootedDeviceCommandError(exitCode: result.exitCode, stderr: Self.stderr(result))
    }
    return try SimctlLaunchctlParser.runningApplications(from: result.stdout)
  }

  /// `uninstall` 하나의 한도 (실측: 부팅 직후 기기에서 38~49초 기다린 뒤 끝났다. 2026-11-10 측정 약 38초, iOS 26.5·27.0 측정
  /// 46~49초. 그 두 배 이상).
  internal static let uninstallTimeout: Duration = .seconds(120)

  /// 사전 목록 확인·재조회는 하지 않는다. 설치돼 있지 않은 앱도 simctl 이 성공으로 끝낸다 (실측 exit 0).
  /// `uninstallTimeout` 이 지나거나 부른 Task 가 취소되면 simctl 을 SIGINT 로 멈추고(`runCancellable`) `.commandFailed`.
  func uninstall(_ bundleID: AppBundleID, on id: VirtualDevice.ID) async throws(SimulatorError) {
    guard let udid = SimctlCommand.validatedUDID(id.rawValue) else {
      throw .deviceNotFound
    }
    let directory = try await self.resolveDeveloperDirectory()
    let result: CommandResult
    do throws(CommandError) {
      result = try await self.command.runCancellable(
        SimctlCommand.xcrun,
        SimctlCommand.uninstall(udid: udid, bundleID: bundleID.rawValue),
        environment: SimctlCommand.environment(base: self.baseEnvironment, developerDirectory: directory),
        timeout: Self.uninstallTimeout,
        onOutput: { _ in }
      )
    } catch {
      switch error {
      case .timedOut, .cancelled: throw .commandFailed
      case .launchFailed: throw .developerToolsUnavailable
      }
    }
    guard result.exitCode == 0 else {
      throw SimctlErrorClassifier.bootedDeviceCommandError(exitCode: result.exitCode, stderr: Self.stderr(result))
    }
  }
}
