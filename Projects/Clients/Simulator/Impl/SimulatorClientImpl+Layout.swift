import Core
import Foundation
import SimulatorInterface

// MARK: - 실행 중인 앱 목록·앱 지우기 (iOS 레이아웃 보기가 쓴다)

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

  /// 사전 목록 확인·재조회는 하지 않는다. 설치돼 있지 않은 앱도 simctl 이 성공으로 끝낸다 (실측 exit 0).
  func uninstall(_ bundleID: AppBundleID, on id: VirtualDevice.ID) async throws(SimulatorError) {
    guard let udid = SimctlCommand.validatedUDID(id.rawValue) else {
      throw .deviceNotFound
    }
    let directory = try await self.resolveDeveloperDirectory()
    let result = try await self.run(
      SimctlCommand.xcrun,
      SimctlCommand.uninstall(udid: udid, bundleID: bundleID.rawValue),
      developerDirectory: directory,
      launchFailure: .developerToolsUnavailable
    )
    guard result.exitCode == 0 else {
      throw SimctlErrorClassifier.bootedDeviceCommandError(exitCode: result.exitCode, stderr: Self.stderr(result))
    }
  }
}
