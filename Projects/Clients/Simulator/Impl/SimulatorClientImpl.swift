import Core
import Foundation
import SimulatorInterface

/// 개발자 디렉터리(`DEVELOPER_DIR`)를 알려 주는 provider. nil 을 돌려주면 `xcode-select` 기본값을 쓴다.
public typealias DeveloperDirectoryProvider = @Sendable () async -> URL?

/// `xcrun simctl` 로 시뮬레이터를 다루는 `SimulatorClient`.
/// provider 는 공개 메서드 한 번에 한 번만 부르고, 그 호출 안의 재조회·앱 열기도 같은 디렉터리를 쓴다.
public struct SimulatorClientImpl: SimulatorClient {
  private let developerDirectory: DeveloperDirectoryProvider?
  private let runner: any CommandRunner
  private let fileExists: @Sendable (URL) -> Bool
  private let baseEnvironment: [String: String]

  /// - Parameter developerDirectory: 쓸 개발자 디렉터리. nil 이거나 nil 을 돌려주면
  ///   물려받은 `DEVELOPER_DIR` 를 지우고 `xcode-select` 기본값을 쓴다.
  public init(developerDirectory: DeveloperDirectoryProvider?) {
    self.init(
      developerDirectory: developerDirectory,
      runner: ProcessCommandRunner(),
      fileExists: { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) },
      baseEnvironment: ProcessInfo.processInfo.environment
    )
  }

  /// 테스트용: 명령 실행·파일 확인·기본 환경을 바꾼다.
  init(
    developerDirectory: DeveloperDirectoryProvider?,
    runner: any CommandRunner,
    fileExists: @escaping @Sendable (URL) -> Bool,
    baseEnvironment: [String: String]
  ) {
    self.developerDirectory = developerDirectory
    self.runner = runner
    self.fileExists = fileExists
    self.baseEnvironment = baseEnvironment
  }

  public func fetchInventory() async throws(SimulatorError) -> DeviceInventory {
    let directory = await self.resolveDeveloperDirectory()
    return try await self.inventory(developerDirectory: directory)
  }

  public func boot(_ id: VirtualDevice.ID) async throws(SimulatorError) {
    try await self.changeState(of: id, arguments: SimctlCommand.boot(udid:), succeedsIn: [.booted, .booting])
  }

  public func shutdown(_ id: VirtualDevice.ID) async throws(SimulatorError) {
    try await self.changeState(
      of: id,
      arguments: SimctlCommand.shutdown(udid:),
      succeedsIn: [.shutdown, .shuttingDown]
    )
  }

  public func openSimulatorApp() async throws(SimulatorError) {
    let directory: URL
    if let provided = await self.resolveDeveloperDirectory() {
      directory = provided
    } else {
      let result = try await self.run(
        SimctlCommand.xcodeSelect,
        SimctlCommand.printDeveloperDirectory(),
        developerDirectory: nil,
        launchFailure: .developerToolsUnavailable
      )
      guard
        result.exitCode == 0,
        let selected = SimulatorAppLocator.developerDirectory(fromXcodeSelectOutput: result.stdout)
      else {
        throw .developerToolsUnavailable
      }
      directory = selected
    }
    guard let app = SimulatorAppLocator.candidates(developerDirectory: directory).first(where: self.fileExists) else {
      throw .simulatorAppNotFound
    }
    let result = try await self.run(
      SimctlCommand.open,
      [app.path(percentEncoded: false)],
      developerDirectory: directory,
      launchFailure: .commandFailed
    )
    if result.exitCode != 0 {
      throw .commandFailed
    }
  }

  private func resolveDeveloperDirectory() async -> URL? {
    guard let developerDirectory = self.developerDirectory else { return nil }
    return await developerDirectory()
  }

  private func inventory(developerDirectory: URL?) async throws(SimulatorError) -> DeviceInventory {
    let result = try await self.run(
      SimctlCommand.xcrun,
      SimctlCommand.list(),
      developerDirectory: developerDirectory,
      launchFailure: .developerToolsUnavailable
    )
    guard result.exitCode == 0 else {
      throw Self.classify(result)
    }
    return try SimctlListDecoder.inventory(from: result.stdout)
  }

  /// 명령이 실패하면 같은 디렉터리로 다시 읽어, 이미 원하는 상태면 성공으로 본다.
  /// 아니면(재조회가 실패해도) 처음 실패를 분류한 에러를 던진다.
  private func changeState(
    of id: VirtualDevice.ID,
    arguments: (String) -> [String],
    succeedsIn targetStates: Set<VirtualDevice.State>
  ) async throws(SimulatorError) {
    guard let udid = SimctlCommand.validatedUDID(id.rawValue) else {
      throw .deviceNotFound
    }
    let directory = await self.resolveDeveloperDirectory()
    let result = try await self.run(
      SimctlCommand.xcrun,
      arguments(udid),
      developerDirectory: directory,
      launchFailure: .developerToolsUnavailable
    )
    guard result.exitCode != 0 else { return }
    let failure = Self.classify(result)
    if
      let inventory = try? await self.inventory(developerDirectory: directory),
      let device = inventory.devices.first(where: { SimctlCommand.validatedUDID($0.id.rawValue) == udid }),
      targetStates.contains(device.state)
    {
      return
    }
    throw failure
  }

  private func run(
    _ executable: URL,
    _ arguments: [String],
    developerDirectory: URL?,
    launchFailure: SimulatorError
  ) async throws(SimulatorError) -> CommandResult {
    let environment = SimctlCommand.environment(base: self.baseEnvironment, developerDirectory: developerDirectory)
    do {
      return try await self.runner.run(executable, arguments, environment: environment)
    } catch {
      throw launchFailure
    }
  }

  private static func classify(_ result: CommandResult) -> SimulatorError {
    SimctlErrorClassifier.error(exitCode: result.exitCode, stderr: String(bytes: result.stderr, encoding: .utf8) ?? "")
  }
}
