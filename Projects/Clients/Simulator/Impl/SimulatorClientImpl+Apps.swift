import Core
import Foundation
import SimulatorInterface

// MARK: - 설치된 앱 목록

public extension SimulatorClientImpl {
  /// 사전 목록 확인·재조회는 하지 않는다 (꺼진 기기·없는 기기는 simctl 의 실패를 분류한다).
  func installedApps(on id: VirtualDevice.ID) async throws(SimulatorError) -> [InstalledApp] {
    guard let udid = SimctlCommand.validatedUDID(id.rawValue) else {
      throw .deviceNotFound
    }
    let directory = try await self.resolveDeveloperDirectory()
    let result = try await self.run(
      SimctlCommand.xcrun,
      SimctlCommand.listApps(udid: udid),
      developerDirectory: directory,
      launchFailure: .developerToolsUnavailable
    )
    guard result.exitCode == 0 else {
      throw SimctlErrorClassifier.listAppsError(exitCode: result.exitCode, stderr: Self.stderr(result))
    }
    return try SimctlAppListDecoder.apps(from: result.stdout)
  }
}
